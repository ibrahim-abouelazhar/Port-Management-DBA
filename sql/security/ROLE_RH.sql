-- Création du Rôle
CREATE ROLE ROLE_RH;

-- Vue Sécurisée
CREATE OR REPLACE VIEW V_PAIE_AFFECTATION AS
SELECT 
    a.id_employe, 
    a.date_affectation, 
    a.heures_travaillees,
    o.libelle as nom_operation
FROM AFFECTATION a
JOIN OPERATION o ON a.id_operation = o.id_operation;

-- ATTRIBUTION DES DROITS (LECTURE SEULE)
-- Le RH doit voir les employés pour les gérer
GRANT SELECT ON EMPLOYE TO ROLE_RH;

-- Le RH doit voir les affectations pour calculer la paie et la surcharge
-- (Mais il ne peut pas créer d'affectations, c'est le rôle OPS)
GRANT SELECT ON AFFECTATION TO ROLE_RH;

GRANT SELECT ON V_PAIE_AFFECTATION TO ROLE_RH;

-- PACKAGE
CREATE OR REPLACE PACKAGE PKG_RH AS
    -- Déclaration des Exceptions (Plage 2002x réservée aux RH)
    EXC_SALAIRE_INVALIDE        EXCEPTION;
    EXC_HIERARCHIE_CYCLIQUE     EXCEPTION;
    EXC_SUPPRESSION_INTERDITE   EXCEPTION;
    EXC_DOUBLON_RH              EXCEPTION;
    EXC_EMPLOYE_INTROUVABLE     EXCEPTION;

    -- Association avec des codes d'erreur Oracle
    PRAGMA EXCEPTION_INIT(EXC_SALAIRE_INVALIDE,      -20020);
    PRAGMA EXCEPTION_INIT(EXC_HIERARCHIE_CYCLIQUE,   -20021);
    PRAGMA EXCEPTION_INIT(EXC_SUPPRESSION_INTERDITE, -20022);
    PRAGMA EXCEPTION_INIT(EXC_DOUBLON_RH,            -20023);
    PRAGMA EXCEPTION_INIT(EXC_EMPLOYE_INTROUVABLE,   -20024);

    -- Procédures exposées (Actions)
    
    -- 1. Recrutement (Insertion propre)
    PROCEDURE RECRUTER_EMPLOYE (
        p_matricule IN VARCHAR2, p_nom IN VARCHAR2, p_prenom IN VARCHAR2,
        p_poste IN VARCHAR2, p_taux_horaire IN NUMBER, p_email IN VARCHAR2,
        p_id_superieur IN NUMBER
    );

    -- 2. Mise à jour Salariale (Transaction critique)
    PROCEDURE MAJ_SALAIRE (
        p_id_employe IN NUMBER, p_nouveau_taux IN NUMBER
    );

    -- 3. Archivage (Soft Delete)
    PROCEDURE ARCHIVER_EMPLOYE (
        p_id_employe IN NUMBER
    );

    -- Fonctions de Calcul (Consultation)
    
    -- Calcul du salaire brut sur une période
    FUNCTION CALCULER_PAIE_MENSUELLE(p_id_employe IN NUMBER, p_mois IN NUMBER, p_annee IN NUMBER) RETURN NUMBER;
    
    -- Vérification de la conformité légale (Heures max)
    FUNCTION EST_SURCHARGE(p_id_employe IN NUMBER) RETURN VARCHAR2;

END PKG_RH;
/

-- Corps du Package
CREATE OR REPLACE PACKAGE BODY PKG_RH AS

    -- Procédure 1 : Recrutement
    PROCEDURE RECRUTER_EMPLOYE (
        p_matricule IN VARCHAR2, p_nom IN VARCHAR2, p_prenom IN VARCHAR2,
        p_poste IN VARCHAR2, p_taux_horaire IN NUMBER, p_email IN VARCHAR2,
        p_id_superieur IN NUMBER
    ) IS
    BEGIN
        -- Validation Métier
        IF p_taux_horaire <= 0 THEN
            RAISE_APPLICATION_ERROR(-20020, 'Erreur : Le taux horaire doit être strictement positif.');
        END IF;

        -- Insertion (ID généré automatiquement par IDENTITY)
        INSERT INTO EMPLOYE (matricule, nom, prenom, poste, taux_horaire, email, id_superieur, statut, date_embauche)
        VALUES (p_matricule, p_nom, p_prenom, p_poste, p_taux_horaire, p_email, p_id_superieur, 'Actif', SYSDATE); -- 'Actif' compatible DML

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Employe ' || p_nom || ' recrute avec succes.');
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20023, 'Erreur : Ce matricule ou email existe déjà.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END RECRUTER_EMPLOYE;

    -- Procédure 2 : Mise à jour Salaire
    PROCEDURE MAJ_SALAIRE (
        p_id_employe IN NUMBER, p_nouveau_taux IN NUMBER
    ) IS
        v_ancien_taux NUMBER;
    BEGIN
        -- Vérification existence et récupération ancien taux
        SELECT taux_horaire INTO v_ancien_taux FROM EMPLOYE WHERE id_employe = p_id_employe;

        IF p_nouveau_taux <= 0 THEN
             RAISE_APPLICATION_ERROR(-20020, 'Erreur : Le nouveau taux doit être positif.');
        END IF;

        UPDATE EMPLOYE SET taux_horaire = p_nouveau_taux WHERE id_employe = p_id_employe;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Salaire mis à jour : ' || v_ancien_taux || ' -> ' || p_nouveau_taux);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20024, 'Employé introuvable.');
    END MAJ_SALAIRE;

    -- Procédure 3 : Archivage
    PROCEDURE ARCHIVER_EMPLOYE (
        p_id_employe IN NUMBER
    ) IS
    BEGIN
        -- Soft Delete : On passe en inactif et salaire à 0
        UPDATE EMPLOYE SET statut = 'Archive', taux_horaire = 0 WHERE id_employe = p_id_employe;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20024, 'Employé introuvable.');
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Employé archivé avec succès.');
    END ARCHIVER_EMPLOYE;

    -- Fonction 1 : Calcul Paie
    FUNCTION CALCULER_PAIE_MENSUELLE (
        p_id_employe IN NUMBER, p_mois IN NUMBER, p_annee IN NUMBER
    ) RETURN NUMBER IS
        v_taux_horaire NUMBER; 
        v_total_heures NUMBER := 0; 
        v_salaire_brut NUMBER := 0;
    BEGIN
        SELECT taux_horaire INTO v_taux_horaire FROM EMPLOYE WHERE id_employe = p_id_employe;
        
        SELECT NVL(SUM(heures_travaillees), 0) INTO v_total_heures 
        FROM AFFECTATION
        WHERE id_employe = p_id_employe 
          AND EXTRACT(MONTH FROM date_affectation) = p_mois 
          AND EXTRACT(YEAR FROM date_affectation) = p_annee;

        v_salaire_brut := v_total_heures * v_taux_horaire;
        RETURN v_salaire_brut;
    EXCEPTION 
        WHEN NO_DATA_FOUND THEN RETURN 0;
    END CALCULER_PAIE_MENSUELLE;

    -- Fonction 2 : Analyse Surcharge
    FUNCTION EST_SURCHARGE (
        p_id_employe IN NUMBER
    ) RETURN VARCHAR2 IS
        v_heures_mois_courant NUMBER;
    BEGIN
        SELECT NVL(SUM(heures_travaillees), 0) INTO v_heures_mois_courant
        FROM AFFECTATION
        WHERE id_employe = p_id_employe AND date_affectation > TRUNC(SYSDATE, 'MM');

        IF v_heures_mois_courant > 190 THEN 
            RETURN 'SURCHARGE'; 
        ELSE 
            RETURN 'NORMAL'; 
        END IF;
    END EST_SURCHARGE;

END PKG_RH;
/

-- TRIGGERS
-- A. Trigger : Intégrité Hiérarchique et Salaire
CREATE OR REPLACE TRIGGER TRG_RH_INTEGRITE_EMPLOYE
BEFORE INSERT OR UPDATE ON EMPLOYE FOR EACH ROW
BEGIN
    -- Règle 1 : Pas d'auto-management
    IF :NEW.id_superieur = :NEW.id_employe THEN
        RAISE_APPLICATION_ERROR(-20021, 'Erreur RH : Un employé ne peut pas être son propre supérieur.');
    END IF;
    
    -- Règle 2 : Cohérence Salaire (Redondance de sécurité avec la procédure)
    IF :NEW.taux_horaire < 0 THEN
        RAISE_APPLICATION_ERROR(-20020, 'Erreur RH : Le taux horaire ne peut être négatif.');
    END IF;
END;
/

-- B. Trigger : Protection contre la suppression physique
-- Interdit le DELETE SQL direct, force l'utilisation de l'archivage
CREATE OR REPLACE TRIGGER TRG_RH_PREVENT_DELETE
BEFORE DELETE ON EMPLOYE FOR EACH ROW
DECLARE 
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM AFFECTATION WHERE id_employe = :OLD.id_employe;
    
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20022, 'INTERDIT : Impossible de supprimer un employé ayant un historique. Passez son statut à ARCHIVE.');
    END IF;
END;
/

-- On donne le droit d'utiliser tout le package RH
GRANT EXECUTE ON PKG_RH TO ROLE_RH;


