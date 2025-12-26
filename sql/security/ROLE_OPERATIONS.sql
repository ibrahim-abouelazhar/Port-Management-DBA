-- Création du Rôle
CREATE ROLE ROLE_OPERATIONS;

-- Vue Sécurisée
CREATE OR REPLACE VIEW V_EMPLOYE_OPS AS
SELECT id_employe, matricule, nom, prenom, poste, statut, telephone 
FROM EMPLOYE;

-- ATTRIBUTION DES DROITS (LECTURE SEULE)
GRANT SELECT ON OPERATION TO ROLE_OPERATIONS;
GRANT SELECT ON AFFECTATION TO ROLE_OPERATIONS;
GRANT SELECT ON CARGAISON TO ROLE_OPERATIONS;
GRANT SELECT ON CONTENEUR TO ROLE_OPERATIONS;
GRANT SELECT ON ESCALE TO ROLE_OPERATIONS;
GRANT SELECT ON NAVIRE TO ROLE_OPERATIONS;
GRANT SELECT ON QUAI TO ROLE_OPERATIONS;

GRANT SELECT ON V_EMPLOYE_OPS TO ROLE_OPERATIONS; -- Accès à la vue, pas la table !

-- Interdiction implicite
-- Pas d'accès à FACTURE, BILLET, ni EMPLOYE (table brute).

-- Package
CREATE OR REPLACE PACKAGE PKG_OPERATIONS AS
    -- Déclaration des Exceptions personnalisées (uniquement Métier)
    EXC_EMPLOYE_OCCUPE      EXCEPTION;
    EXC_DATE_INVALIDE       EXCEPTION;
    EXC_CAPACITE_DEPASSEE   EXCEPTION;
    EXC_DONNEE_INTROUVABLE  EXCEPTION;
    EXC_DOUBLON_AFFECTATION EXCEPTION;

    -- Association avec des codes d'erreur Oracle (-20001 à -20999)
    PRAGMA EXCEPTION_INIT(EXC_EMPLOYE_OCCUPE, -20001);
    PRAGMA EXCEPTION_INIT(EXC_DATE_INVALIDE, -20002);
    PRAGMA EXCEPTION_INIT(EXC_CAPACITE_DEPASSEE, -20003);
    PRAGMA EXCEPTION_INIT(EXC_DONNEE_INTROUVABLE, -20004);
    PRAGMA EXCEPTION_INIT(EXC_DOUBLON_AFFECTATION, -20005);

    -- Procédures exposées
    PROCEDURE ENREGISTRER_OPERATION(
        p_libelle IN VARCHAR2, p_type_op IN VARCHAR2, p_id_escale IN NUMBER, p_id_cargaison IN NUMBER DEFAULT NULL
    );
    
    PROCEDURE AFFECTER_EMPLOYE(
        p_id_employe IN NUMBER, p_id_operation IN NUMBER, p_role IN VARCHAR2, p_heures IN NUMBER
    );
    
    PROCEDURE AJOUTER_CARGAISON(
        p_libelle IN VARCHAR2, p_poids IN NUMBER, p_dangereux IN NUMBER, p_id_navire IN NUMBER
    );

    -- Fonction de vérification
    FUNCTION VERIFIER_POIDS(p_id_navire IN NUMBER, p_poids_ajout IN NUMBER) RETURN NUMBER;

END PKG_OPERATIONS;
/

-- Corps du Package
CREATE OR REPLACE PACKAGE BODY PKG_OPERATIONS AS

    -- Fonction privée pour vérifier le poids
    -- Vérifier le Tonnage
    -- Impossible de déclarer une opération (ex: déchargement) avant que le navire soit arrivé.
    FUNCTION VERIFIER_POIDS(
        p_id_navire IN NUMBER, 
        p_poids_ajout IN NUMBER) 
    RETURN NUMBER IS
        v_poids_actuel NUMBER := 0;
        v_tonnage_max  NUMBER := 0;
    BEGIN
        -- Récupérer la capacité max
        SELECT tonnage_max INTO v_tonnage_max 
        FROM NAVIRE_COMMERCE WHERE id_navire = p_id_navire;

        -- Calculer ce qui est déjà chargé
        SELECT NVL(SUM(poids_total), 0) INTO v_poids_actuel
        FROM CARGAISON WHERE id_navire = p_id_navire;

        IF (v_poids_actuel + p_poids_ajout) > v_tonnage_max THEN
            RETURN 0; -- Surcharge
        ELSE
            RETURN 1; -- OK
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 1; 
    END VERIFIER_POIDS;


    -- A. Enregistrer une Opération
    PROCEDURE ENREGISTRER_OPERATION(
        p_libelle IN VARCHAR2, 
        p_type_op IN VARCHAR2, 
        p_id_escale IN NUMBER, 
        p_id_cargaison IN NUMBER DEFAULT NULL -- Optionnel
    ) IS
        v_date_arrivee DATE;
    BEGIN
        -- Vérification : L'escale existe-t-elle et est-elle active ?
        SELECT date_arrivee_reelle INTO v_date_arrivee
        FROM ESCALE WHERE id_escale = p_id_escale;

        -- Si la date d'arrivée est vide, le navire n'est pas là.
        IF v_date_arrivee IS NULL THEN
            -- On lève l'erreur -20002 qui correspond à EXC_DATE_INVALIDE
            RAISE_APPLICATION_ERROR(-20002, 'Impossible : Le navire n''est pas encore arrivé (Date Arrivée vide).');
        END IF;

        -- Insertion
        INSERT INTO OPERATION (libelle, type_operation, date_operation, id_escale, id_cargaison)
        VALUES (p_libelle, p_type_op, SYSDATE, p_id_escale, p_id_cargaison);
        
        COMMIT; -- Validation de la transaction
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20004, 'Escale introuvable.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;        
    END ENREGISTRER_OPERATION;

    -- B. Affecter un Employé
    -- Vérifie que l'employé est actif avant de l'affecter.
    PROCEDURE AFFECTER_EMPLOYE(
        p_id_employe IN NUMBER, 
        p_id_operation IN NUMBER, 
        p_role IN VARCHAR2, 
        p_heures IN NUMBER
    ) IS
        v_statut VARCHAR2(20);
        v_count  NUMBER;
    BEGIN
        -- 1. Vérifier si l'employé est 'Actif' (via la table brute ou la vue)    
        SELECT statut INTO v_statut FROM EMPLOYE WHERE id_employe = p_id_employe;
        
        IF v_statut != 'Actif' THEN
            -- Erreur -20001 (EXC_EMPLOYE_OCCUPE)
            RAISE_APPLICATION_ERROR(-20001, 'Employé non disponible (Statut : ' || v_statut || ')');
        END IF;

        -- 2. Vérifier s'il n'est pas déjà sur cette opération
        SELECT COUNT(*) INTO v_count FROM AFFECTATION 
        WHERE id_employe = p_id_employe AND id_operation = p_id_operation;

        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Employé déjà affecté à cette opération.');
        END IF;
        
        -- 3. Insertion
        INSERT INTO AFFECTATION (id_employe, id_operation, role, heures_travaillees)
        VALUES (p_id_employe, p_id_operation, p_role, p_heures);
        
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
             ROLLBACK;
             RAISE_APPLICATION_ERROR(-20004, 'Employé introuvable.');
    END AFFECTER_EMPLOYE;

    -- C. Déclarer une Cargaison
    -- Pour préparer le chargement.
    PROCEDURE AJOUTER_CARGAISON(
        p_libelle IN VARCHAR2, 
        p_poids IN NUMBER, 
        p_dangereux IN NUMBER, 
        p_id_navire IN NUMBER
    ) IS
    BEGIN
        IF VERIFIER_POIDS(p_id_navire, p_poids) = 0 THEN
            -- Erreur -20003 (EXC_CAPACITE_DEPASSEE)
            RAISE_APPLICATION_ERROR(-20003, 'Surcharge du navire ! Capacité dépassée.');
        END IF;

        INSERT INTO CARGAISON (libelle, poids_total, est_dangereux, id_navire)
        VALUES (p_libelle, p_poids, p_dangereux, p_id_navire);
        COMMIT;
    END AJOUTER_CARGAISON;

END PKG_OPERATIONS;
/

-- Triggers (Automatisation & Contrôle)

-- A. Trigger : Cohérence des Dates d'Opération
--Impossible de déclarer une opération (ex: déchargement) avant que le navire soit arrivé.
CREATE OR REPLACE TRIGGER TRG_OPS_DATE_COHERENCE
BEFORE INSERT ON OPERATION
FOR EACH ROW
DECLARE
    v_date_arrivee DATE;
    v_date_depart  DATE;
BEGIN
    -- Récupérer les dates réelles de l'escale
    SELECT date_arrivee_reelle, date_depart_reelle 
    INTO v_date_arrivee, v_date_depart
    FROM ESCALE 
    WHERE id_escale = :NEW.id_escale;

    -- Règle 1 : Pas d'opération avant l'arrivée
    IF :NEW.date_operation < v_date_arrivee THEN
        RAISE_APPLICATION_ERROR(-20002, 'Erreur: L''opération ne peut pas avoir lieu avant l''arrivée du navire (ATA).');
    END IF;

    -- Règle 2 : Pas d'opération après le départ (si le navire est déjà parti)
    IF v_date_depart IS NOT NULL AND :NEW.date_operation > v_date_depart THEN
        RAISE_APPLICATION_ERROR(-20002, 'Erreur: Le navire est déjà parti, impossible d''ajouter une opération.');
    END IF;
END;
/

-- B. Trigger : Sécurité Marchandise Dangereuse
-- Si on manipule une cargaison dangereuse, on force le type d'opération à inclure une mention "SÉCURITÉ".
CREATE OR REPLACE TRIGGER TRG_OPS_SEC_DANGER
BEFORE INSERT ON OPERATION
FOR EACH ROW
DECLARE
    v_est_dangereux NUMBER(1);
BEGIN
    -- Si l'opération concerne une cargaison
    IF :NEW.id_cargaison IS NOT NULL THEN
        SELECT est_dangereux INTO v_est_dangereux
        FROM CARGAISON WHERE id_cargaison = :NEW.id_cargaison;

        -- Si c'est dangereux et que le libellé ne mentionne pas "DANGER"
        IF v_est_dangereux = 1 AND UPPER(:NEW.libelle) NOT LIKE '%DANGER%' THEN
            -- On ajoute automatiquement l'avertissement
            :NEW.libelle := '[DANGER] ' || :NEW.libelle;
        END IF;
    END IF;
END;
/

-- On donne le droit d'utiliser tout le package d'opérations
GRANT EXECUTE ON PKG_OPERATIONS TO ROLE_OPERATIONS;


