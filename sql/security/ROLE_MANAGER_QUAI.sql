-- Création du Rôle
CREATE ROLE ROLE_MANAGER_QUAI;

CREATE SEQUENCE SEQ_ESCALE START WITH 100 INCREMENT BY 1;

-- ATTRIBUTION DES DROITS (LECTURE SEULE)
-- Le Manager a besoin de voir tout le port pour planifier
GRANT SELECT ON QUAI TO ROLE_MANAGER_QUAI;
GRANT SELECT ON ESCALE TO ROLE_MANAGER_QUAI;
GRANT SELECT ON RESERVATION TO ROLE_MANAGER_QUAI;
GRANT SELECT ON NAVIRE TO ROLE_MANAGER_QUAI;
GRANT SELECT ON NAVIRE_COMMERCE TO ROLE_MANAGER_QUAI;
GRANT SELECT ON NAVIRE_PASSAGER TO ROLE_MANAGER_QUAI;
GRANT SELECT ON NAVIRE_PECHE TO ROLE_MANAGER_QUAI;
GRANT SELECT ON FREQUENTATION_ZONE TO ROLE_MANAGER_QUAI;
GRANT SELECT ON ZONE_PECHE TO ROLE_MANAGER_QUAI;

-- PACKAGE
CREATE OR REPLACE PACKAGE PKG_MANAGER_QUAI AS
    -- Déclaration des Exceptions (Plage 2003x réservée à la Capitainerie)
    EXC_TYPE_NAVIRE_INVALIDE EXCEPTION;
    EXC_RISQUE_ECHOUAGE      EXCEPTION;
    EXC_NAVIRE_TROP_LONG     EXCEPTION;
    EXC_QUAI_OCCUPE          EXCEPTION;
    EXC_DONNEE_INTROUVABLE   EXCEPTION;

    -- Association avec des codes d'erreur Oracle
    PRAGMA EXCEPTION_INIT(EXC_TYPE_NAVIRE_INVALIDE, -20030);
    PRAGMA EXCEPTION_INIT(EXC_RISQUE_ECHOUAGE,      -20031);
    PRAGMA EXCEPTION_INIT(EXC_NAVIRE_TROP_LONG,     -20032);
    PRAGMA EXCEPTION_INIT(EXC_QUAI_OCCUPE,          -20033);
    PRAGMA EXCEPTION_INIT(EXC_DONNEE_INTROUVABLE,   -20034);

    -- Procédures exposées   
    -- 1. Enregistrement d'un nouveau navire et de ses spécificités
    PROCEDURE ENREGISTRER_NAVIRE (
        p_nom IN VARCHAR2, p_num_imo IN VARCHAR2, p_pavillon IN VARCHAR2,
        p_longueur IN NUMBER, p_tirant IN NUMBER, 
        p_type IN VARCHAR2, -- 'COMMERCE', 'PASSAGER', 'PECHE'
        p_param_spe_1 IN NUMBER DEFAULT 0, -- Tonnage / Capacité / Stockage
        p_param_spe_2 IN VARCHAR2 DEFAULT NULL -- Nb Conteneurs / Cabines / Type Pêche (Converti en fonction du type)
    );

    -- 2. Création d'une demande de réservation
    PROCEDURE CREER_RESERVATION (
        p_id_navire IN NUMBER, 
        p_date_debut IN TIMESTAMP, 
        p_date_fin IN TIMESTAMP, 
        p_motif IN VARCHAR2
    );

    -- 3. Planification (Validation) d'une escale
    PROCEDURE PLANIFIER_ESCALE (
        p_id_escale IN NUMBER, p_id_quai IN NUMBER, p_date_arrivee IN TIMESTAMP
    );

    PROCEDURE VALIDER_RESERVATION (
        p_id_reservation IN NUMBER,
        p_id_quai IN NUMBER
    );

    -- Fonctions de vérification (Publiques pour consultation)
    FUNCTION EST_QUAI_COMPATIBLE(p_id_escale IN NUMBER, p_id_quai IN NUMBER) RETURN NUMBER;
    FUNCTION VERIFIER_DISPO_QUAI(p_id_quai NUMBER, p_date_debut TIMESTAMP, p_date_fin TIMESTAMP) RETURN NUMBER;

END PKG_MANAGER_QUAI;
/

-- Corps du Package
CREATE OR REPLACE PACKAGE BODY PKG_MANAGER_QUAI AS

    -- Fonction : Vérifie si les dimensions du navire collent avec le quai
    FUNCTION EST_QUAI_COMPATIBLE(p_id_escale IN NUMBER, p_id_quai IN NUMBER) RETURN NUMBER IS
        v_tirant_navire NUMBER; v_longueur_navire NUMBER; 
        v_prof_quai NUMBER; v_long_quai NUMBER; 
        v_id_navire NUMBER;
    BEGIN
        -- Récupération Navire
        SELECT id_navire INTO v_id_navire FROM ESCALE WHERE id_escale = p_id_escale;
        SELECT tirant_eau, longueur INTO v_tirant_navire, v_longueur_navire FROM NAVIRE WHERE id_navire = v_id_navire;
        
        -- Récupération Quai
        SELECT profondeur_bassin, longueur_max INTO v_prof_quai, v_long_quai FROM QUAI WHERE id_quai = p_id_quai;

        -- Règles : Marge de sécurité 0.5m pour la profondeur
        IF v_tirant_navire > (v_prof_quai - 0.5) THEN RETURN 0; END IF; -- Trop profond
        IF v_longueur_navire > v_long_quai THEN RETURN 0; END IF;       -- Trop long

        RETURN 1; -- OK
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END EST_QUAI_COMPATIBLE;

    -- Fonction : Vérifie les conflits de planning
    FUNCTION VERIFIER_DISPO_QUAI(p_id_quai NUMBER, p_date_debut TIMESTAMP, p_date_fin TIMESTAMP) RETURN NUMBER IS 
        v_conflits NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_conflits FROM ESCALE
        WHERE id_quai = p_id_quai 
          AND statut_escale IN ('Prevue', 'En cours') -- Valeurs compatibles DML
          AND (
              (p_date_debut BETWEEN date_arrivee_prevue AND date_depart_prevue)
              OR (p_date_fin BETWEEN date_arrivee_prevue AND date_depart_prevue)
              OR (date_arrivee_prevue BETWEEN p_date_debut AND p_date_fin)
          );

        IF v_conflits > 0 THEN RETURN 0; ELSE RETURN 1; END IF;
    END VERIFIER_DISPO_QUAI;

    -- Procédure A : Enregistrer Navire
    PROCEDURE ENREGISTRER_NAVIRE (
        p_nom IN VARCHAR2, p_num_imo IN VARCHAR2, p_pavillon IN VARCHAR2,
        p_longueur IN NUMBER, p_tirant IN NUMBER, p_type IN VARCHAR2,
        p_param_spe_1 IN NUMBER DEFAULT 0, p_param_spe_2 IN VARCHAR2 DEFAULT NULL
    ) IS
        v_id_navire NUMBER;
    BEGIN
        -- Insertion Mère
        INSERT INTO NAVIRE (nom, num_imo, pavillon, longueur, tirant_eau)
        VALUES (p_nom, p_num_imo, p_pavillon, p_longueur, p_tirant)
        RETURNING id_navire INTO v_id_navire;

        -- Insertion Fille selon type
        IF UPPER(p_type) = 'COMMERCE' THEN
            INSERT INTO NAVIRE_COMMERCE (id_navire, tonnage_max, capacite_conteneurs) 
            VALUES (v_id_navire, p_param_spe_1, TO_NUMBER(p_param_spe_2));
        ELSIF UPPER(p_type) = 'PASSAGER' THEN
            INSERT INTO NAVIRE_PASSAGER (id_navire, capacite_passagers, nb_cabines) 
            VALUES (v_id_navire, p_param_spe_1, TO_NUMBER(p_param_spe_2));
        ELSIF UPPER(p_type) = 'PECHE' THEN
            INSERT INTO NAVIRE_PECHE (id_navire, capacite_stockage, type_peche) 
            VALUES (v_id_navire, p_param_spe_1, p_param_spe_2);
        ELSE
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20030, 'Type de navire invalide (COMMERCE, PASSAGER, PECHE).');
        END IF;
        COMMIT;
    END ENREGISTRER_NAVIRE;

    -- Procédure B : Créer Réservation
    PROCEDURE CREER_RESERVATION (
        p_id_navire IN NUMBER, p_date_debut IN TIMESTAMP, p_date_fin IN TIMESTAMP, p_motif IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO RESERVATION (date_demande, date_debut_souhaitee, date_fin_souhaitee, motif, statut, id_navire)
        VALUES (SYSTIMESTAMP, p_date_debut, p_date_fin, p_motif, 'En attente', p_id_navire);
        COMMIT;
    END CREER_RESERVATION;

    -- Procédure C : Planifier Escale
    PROCEDURE PLANIFIER_ESCALE (
        p_id_escale IN NUMBER, p_id_quai IN NUMBER, p_date_arrivee IN TIMESTAMP
    ) IS
    BEGIN
        -- 1. Vérification Physique
        IF EST_QUAI_COMPATIBLE(p_id_escale, p_id_quai) = 0 THEN
            RAISE_APPLICATION_ERROR(-20031, 'Incompatible : Navire trop grand ou profond pour ce quai.');
        END IF;

        -- 2. Vérification Temporelle (On estime une durée par défaut de 48h si pas précisé, pour le check)
        IF VERIFIER_DISPO_QUAI(p_id_quai, p_date_arrivee, p_date_arrivee + 2) = 0 THEN
            RAISE_APPLICATION_ERROR(-20033, 'Indisponible : Le quai est déjà occupé à cette date.');
        END IF;

        -- 3. Mise à jour
        UPDATE ESCALE 
        SET id_quai = p_id_quai, 
            date_arrivee_prevue = p_date_arrivee,
            date_depart_prevue = p_date_arrivee + 2,
            statut_escale = 'Prevue' 
        WHERE id_escale = p_id_escale;
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20034, 'Escale introuvable.');
        END IF;

        COMMIT;
    END PLANIFIER_ESCALE;

    -- Procédure D : Valider Réservation
    PROCEDURE VALIDER_RESERVATION (
        p_id_reservation IN NUMBER,
        p_id_quai IN NUMBER
    ) IS
        v_id_navire NUMBER;
        v_date_debut TIMESTAMP;
        v_date_fin TIMESTAMP;
    BEGIN
        -- 1. Récupérer les infos
        SELECT id_navire, date_debut_souhaitee, date_fin_souhaitee 
        INTO v_id_navire, v_date_debut, v_date_fin
        FROM RESERVATION
        WHERE id_reservation = p_id_reservation;
    
        -- 2. Update statut
        UPDATE RESERVATION 
        SET statut = 'Confirmee' 
        WHERE id_reservation = p_id_reservation;
    
        -- 3. Créer l'Escale (Utilisation de SEQ_ESCALE créée précédemment)
        INSERT INTO ESCALE (
            id_escale,   
            id_navire, 
            id_quai, 
            date_arrivee_prevue, 
            date_depart_prevue, 
            statut_escale,
            id_reservation
        ) VALUES (
            SEQ_ESCALE.NEXTVAL, 
            v_id_navire,
            p_id_quai,
            v_date_debut,
            v_date_fin,
            'Planifiee',
            p_id_reservation
        );
    
        COMMIT;
    END VALIDER_RESERVATION;

END PKG_MANAGER_QUAI;
/

-- TRIGGERS
-- A. Trigger : Génération Référence Escale (Si NULL)
CREATE OR REPLACE TRIGGER TRG_GENERATE_REF_ESCALE
BEFORE INSERT ON ESCALE FOR EACH ROW
BEGIN
    IF :NEW.num_reference IS NULL THEN
        -- Utilise la séquence (assurez-vous qu'elle existe)
        :NEW.num_reference := 'ESC-' || TO_CHAR(SYSDATE, 'YYYY') || '-' || LPAD(ROUND(DBMS_RANDOM.VALUE(1,9999)), 4, '0');
    END IF;
END;
/

-- B. Trigger : Sécurité Physique (Dernière ligne de défense)
CREATE OR REPLACE TRIGGER TRG_SEC_VERIF_QUAI
BEFORE INSERT OR UPDATE OF id_quai ON ESCALE FOR EACH ROW
DECLARE 
    v_prof_quai NUMBER; 
    v_tirant_navire NUMBER;
BEGIN
    IF :NEW.id_quai IS NOT NULL THEN
        SELECT profondeur_bassin INTO v_prof_quai FROM QUAI WHERE id_quai = :NEW.id_quai;
        SELECT tirant_eau INTO v_tirant_navire FROM NAVIRE WHERE id_navire = :NEW.id_navire;
        
        IF v_tirant_navire > v_prof_quai THEN
            RAISE_APPLICATION_ERROR(-20031, 'ALERTE SECURITE : Risque d''echouage. Tirant d''eau > Profondeur Quai.');
        END IF;
    END IF;
END;
/

-- C. Trigger : Audit Planning
CREATE OR REPLACE TRIGGER TRG_AUDIT_PLANNING
AFTER UPDATE OF date_arrivee_prevue ON ESCALE FOR EACH ROW
BEGIN
    DBMS_OUTPUT.PUT_LINE('Planning modifie pour l''escale ' || :OLD.num_reference ||
                         ' : Ancienne date ' || TO_CHAR(:OLD.date_arrivee_prevue, 'DD/MM/YYYY HH24:MI') ||
                         ' -> Nouvelle date ' || TO_CHAR(:NEW.date_arrivee_prevue, 'DD/MM/YYYY HH24:MI'));
END;
/

-- On donne le droit d'utiliser tout le package Capitainerie
GRANT EXECUTE ON PKG_MANAGER_QUAI TO ROLE_MANAGER_QUAI;