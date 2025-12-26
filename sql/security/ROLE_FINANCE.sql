-- Création du Rôle
CREATE ROLE ROLE_FINANCE;

-- Vue Sécurisée
CREATE OR REPLACE VIEW V_EMPLOYE_FINANCE AS
SELECT id_employe, nom, prenom, taux_horaire 
FROM EMPLOYE;

-- ATTRIBUTION DES DROITS (LECTURE SEULE)
-- La Finance doit voir les escales et les opérations pour facturer
GRANT SELECT ON ESCALE TO ROLE_FINANCE;
GRANT SELECT ON OPERATION TO ROLE_FINANCE;
GRANT SELECT ON AFFECTATION TO ROLE_FINANCE;
GRANT SELECT ON FACTURE TO ROLE_FINANCE;

GRANT SELECT ON V_EMPLOYE_FINANCE TO ROLE_FINANCE;

-- PACKAGE
CREATE OR REPLACE PACKAGE PKG_FINANCE AS
    -- Déclaration des Exceptions (Plage 2001x réservée à la Finance)
    EXC_ESCALE_ANNULEE          EXCEPTION;
    EXC_ESCALE_INEXISTANTE      EXCEPTION;
    EXC_FACTURE_DEJA_PAYEE      EXCEPTION;
    EXC_FACTURE_INEXISTANTE     EXCEPTION;
    EXC_SUPPRESSION_INTERDITE   EXCEPTION;

    -- Association avec des codes d'erreur Oracle
    PRAGMA EXCEPTION_INIT(EXC_ESCALE_ANNULEE,        -20010);
    PRAGMA EXCEPTION_INIT(EXC_ESCALE_INEXISTANTE,    -20011);
    PRAGMA EXCEPTION_INIT(EXC_FACTURE_DEJA_PAYEE,    -20012);
    PRAGMA EXCEPTION_INIT(EXC_FACTURE_INEXISTANTE,   -20013);
    PRAGMA EXCEPTION_INIT(EXC_SUPPRESSION_INTERDITE, -20014);

    -- Procédures exposées (Actions)
    
    -- 1. Création d'une facture
    PROCEDURE CREER_FACTURE (
        p_montant IN NUMBER, p_date_echeance IN TIMESTAMP, p_id_escale IN NUMBER
    );

    -- 2. Enregistrement d'un paiement
    PROCEDURE PAYER_FACTURE (
        p_id_facture IN NUMBER
    );

    -- Fonctions de Calcul (Consultation)
    
    -- Calcul du coût complet (Matériel + Main d'œuvre)
    FUNCTION CALCULER_COUT_TOTAL_ESCALE(p_id_escale IN NUMBER) RETURN NUMBER;
    
    -- Reporting CA
    FUNCTION CHIFFRE_AFFAIRES_PERIODE(p_date_debut IN TIMESTAMP, p_date_fin IN TIMESTAMP) RETURN NUMBER;

END PKG_FINANCE;
/

-- Corps du Package
CREATE OR REPLACE PACKAGE BODY PKG_FINANCE AS

    -- Procédure 1 : Créer Facture
    PROCEDURE CREER_FACTURE (
        p_montant IN NUMBER, p_date_echeance IN TIMESTAMP, p_id_escale IN NUMBER
    ) IS
        v_statut_escale VARCHAR2(50);
    BEGIN
        -- Vérification de l'escale
        SELECT statut_escale INTO v_statut_escale FROM ESCALE WHERE id_escale = p_id_escale;
        
        -- On ne facture pas une escale annulée
        IF UPPER(v_statut_escale) LIKE '%ANNULE%' THEN
            RAISE_APPLICATION_ERROR(-20010, 'Impossible de facturer une escale annulée.');
        END IF;

        -- Insertion (ID généré par Identity)
        INSERT INTO FACTURE (montant_total, date_emission, date_echeance, statut_paiement, id_escale)
        VALUES (p_montant, SYSTIMESTAMP, p_date_echeance, 'En attente', p_id_escale);

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Facture créée avec succès pour l''escale ' || p_id_escale);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20011, 'L''escale spécifiée n''existe pas.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END CREER_FACTURE;

    -- Procédure 2 : Payer Facture
    PROCEDURE PAYER_FACTURE (
        p_id_facture IN NUMBER
    ) IS
        v_statut_actuel VARCHAR2(50);
    BEGIN
        -- Verrouillage de la ligne pour éviter double paiement concurrent
        SELECT statut_paiement INTO v_statut_actuel 
        FROM FACTURE WHERE id_facture = p_id_facture FOR UPDATE;

        IF UPPER(v_statut_actuel) = 'PAYEE' THEN
            RAISE_APPLICATION_ERROR(-20012, 'Cette facture est déjà réglée.');
        END IF;

        UPDATE FACTURE SET statut_paiement = 'Payee' WHERE id_facture = p_id_facture;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Paiement enregistré pour la facture ' || p_id_facture);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20013, 'Facture introuvable.');
    END PAYER_FACTURE;

    -- Fonction 1 : Coût Total
    FUNCTION CALCULER_COUT_TOTAL_ESCALE (
        p_id_escale IN NUMBER
    ) RETURN NUMBER IS
        v_cout_materiel NUMBER := 0;
        v_cout_humain   NUMBER := 0;
        v_total         NUMBER := 0;
    BEGIN
        -- 1. Coût Matériel des opérations
        SELECT NVL(SUM(cout_materiel), 0) INTO v_cout_materiel 
        FROM OPERATION WHERE id_escale = p_id_escale;
        
        -- 2. Coût Humain (Heures * Taux Horaire)
        -- Jointure complexe : Affectation -> Operation -> Escale
        SELECT NVL(SUM(a.heures_travaillees * e.taux_horaire), 0) INTO v_cout_humain
        FROM AFFECTATION a 
        JOIN V_EMPLOYE_FINANCE e ON a.id_employe = e.id_employe
        JOIN OPERATION o ON a.id_operation = o.id_operation 
        WHERE o.id_escale = p_id_escale;

        v_total := v_cout_materiel + v_cout_humain;
        RETURN v_total;
    EXCEPTION 
        WHEN OTHERS THEN RETURN -1;
    END CALCULER_COUT_TOTAL_ESCALE;

    -- Fonction 2 : Chiffre d'Affaires
    FUNCTION CHIFFRE_AFFAIRES_PERIODE (
        p_date_debut IN TIMESTAMP, p_date_fin IN TIMESTAMP
    ) RETURN NUMBER IS
        v_ca NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(montant_total), 0) INTO v_ca 
        FROM FACTURE
        WHERE date_emission BETWEEN p_date_debut AND p_date_fin 
          AND UPPER(statut_paiement) = 'PAYEE';
          
        RETURN v_ca;
    END CHIFFRE_AFFAIRES_PERIODE;

END PKG_FINANCE;
/

-- TRIGGERS
-- A. Trigger : Sécurité Facture (Interdiction de suppression si payée)
CREATE OR REPLACE TRIGGER TRG_SECURITE_FACTURE
BEFORE DELETE ON FACTURE FOR EACH ROW
BEGIN
    IF UPPER(:OLD.statut_paiement) = 'PAYEE' THEN
        RAISE_APPLICATION_ERROR(-20014, 'INTERDIT : Impossible de supprimer une facture déjà payée (Traçabilité comptable).');
    END IF;
END;
/

-- B. Trigger : Mise à jour automatique retard
-- Se déclenche avant modification pour vérifier l'échéance
CREATE OR REPLACE TRIGGER TRG_CHECK_RETARD_PAIEMENT
BEFORE UPDATE ON FACTURE FOR EACH ROW
BEGIN
    -- Si la facture est en attente mais que la date d'échéance est passée
    IF :NEW.statut_paiement = 'En attente' AND :NEW.date_echeance < SYSTIMESTAMP THEN
        :NEW.statut_paiement := 'En retard';
    END IF;
END;
/

-- On donne le droit d'utiliser tout le package Finance
GRANT EXECUTE ON PKG_FINANCE TO ROLE_FINANCE;