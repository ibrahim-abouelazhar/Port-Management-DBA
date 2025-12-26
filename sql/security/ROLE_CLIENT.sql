-- Création du Rôle
CREATE ROLE ROLE_CLIENT;

-- Vue Sécurisée
-- A. VUE NAVIRE
CREATE OR REPLACE VIEW V_INFO_NAVIRE AS
SELECT id_navire, nom, num_imo, pavillon, longueur, tirant_eau
FROM NAVIRE;

-- B. Vue sur les Quais
-- Il doit savoir quels quais existent pour faire sa demande
CREATE OR REPLACE VIEW V_INFOS_QUAIS AS
SELECT id_quai, nom, longueur_max, profondeur_bassin, capacite_tonnage
FROM QUAI;

-- C. Vue sur ses reservations
CREATE OR REPLACE VIEW V_MES_RESERVATIONS AS
SELECT 
    r.id_reservation,
    r.date_demande,
    r.date_debut_souhaitee,
    r.date_fin_souhaitee,
    r.statut,
    r.motif,
    r.priorite,
    r.id_navire,
    q.nom AS nom_quai_attribue
FROM RESERVATION r
LEFT JOIN ESCALE e ON r.id_reservation = e.id_reservation
LEFT JOIN QUAI q ON e.id_quai = q.id_quai;

-- D. VUE ESCALES
CREATE OR REPLACE VIEW V_MES_ESCALES AS
SELECT 
    e.id_escale,
    e.date_arrivee_prevue,
    e.date_arrivee_reelle, 
    e.date_depart_reelle,  
    e.statut_escale,
    e.id_navire,
    q.nom AS quai_utilise
FROM ESCALE e
LEFT JOIN QUAI q ON e.id_quai = q.id_quai;

-- E. VUE FACTURES
CREATE OR REPLACE VIEW V_MES_FACTURES AS
SELECT 
    f.id_facture, 
    f.montant_total, 
    f.date_emission, 
    f.date_echeance, 
    f.statut_paiement, 
    e.id_navire
FROM FACTURE f
JOIN ESCALE e ON f.id_escale = e.id_escale;

-- ATTRIBUTION DES DROITS (LECTURE SEULE)
GRANT SELECT ON V_INFO_NAVIRE TO ROLE_CLIENT;
GRANT SELECT ON V_INFOS_QUAIS TO ROLE_CLIENT;
GRANT SELECT ON V_MES_RESERVATIONS TO ROLE_CLIENT;
GRANT SELECT ON V_MES_ESCALES TO ROLE_CLIENT;
GRANT SELECT ON V_MES_FACTURES TO ROLE_CLIENT;

-- Package
CREATE OR REPLACE PACKAGE PKG_CLIENT AS
    -- Déclaration des Exceptions personnalisées
    EXC_DATE_PASSE           EXCEPTION; -- -20041
    EXC_ANNULATION_INTERDITE EXCEPTION; -- -20042
    EXC_DROITS_INSUFFISANTS  EXCEPTION; -- -20043
    EXC_PERIODE_INCOHERENTE  EXCEPTION; -- -20044
    EXC_CONFLIT_RESERVATION  EXCEPTION; -- -20045

    -- Association avec des codes d'erreur Oracle
    PRAGMA EXCEPTION_INIT(EXC_DATE_PASSE,           -20041);
    PRAGMA EXCEPTION_INIT(EXC_ANNULATION_INTERDITE, -20042);
    PRAGMA EXCEPTION_INIT(EXC_DROITS_INSUFFISANTS,  -20043);
    PRAGMA EXCEPTION_INIT(EXC_PERIODE_INCOHERENTE,  -20044);
    PRAGMA EXCEPTION_INIT(EXC_CONFLIT_RESERVATION,  -20045);

    -- 2. Procédure de Création (Demande)
    PROCEDURE CREER_RESERVATION (
        p_id_navire IN NUMBER,
        p_date_debut IN TIMESTAMP,
        p_date_fin IN TIMESTAMP,
        p_motif IN VARCHAR2
    );

    -- 3. Procédure d'Annulation
    PROCEDURE ANNULER_RESERVATION (
        p_id_navire IN NUMBER, 
        p_id_reservation IN NUMBER
    );

END PKG_CLIENT;
/

-- Corps du Package
CREATE OR REPLACE PACKAGE BODY PKG_CLIENT AS

    PROCEDURE CREER_RESERVATION (
        p_id_navire IN NUMBER,
        p_date_debut IN TIMESTAMP,
        p_date_fin IN TIMESTAMP,
        p_motif IN VARCHAR2
    ) IS
        v_count NUMBER;
    BEGIN
        -- Vérifications temporelles
        IF p_date_debut < SYSTIMESTAMP THEN
            RAISE_APPLICATION_ERROR(-20041, 'Erreur : La date de début ne peut pas être dans le passé.');
        END IF;
        
        IF p_date_fin <= p_date_debut THEN
            RAISE_APPLICATION_ERROR(-20044, 'Erreur : La date de fin doit être postérieure à la date de début.');
        END IF;

        -- Vérification des conflits
        SELECT COUNT(*) INTO v_count
        FROM RESERVATION
        WHERE id_navire = p_id_navire
          AND statut IN ('En attente', 'Confirmee')
          AND (
              (p_date_debut BETWEEN date_debut_souhaitee AND date_fin_souhaitee) OR
              (p_date_fin BETWEEN date_debut_souhaitee AND date_fin_souhaitee) OR
              (date_debut_souhaitee BETWEEN p_date_debut AND p_date_fin)
          );

        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20045, 'Erreur : Ce navire a déjà une demande en cours sur cette période.');
        END IF;

        -- Insertion
        INSERT INTO RESERVATION (
            date_demande, date_debut_souhaitee, date_fin_souhaitee, 
            motif, priorite, statut, id_navire
        ) VALUES (
            SYSTIMESTAMP, p_date_debut, p_date_fin, 
            p_motif, 'Normale', 'En attente', p_id_navire
        );
        COMMIT;
    END CREER_RESERVATION;


    PROCEDURE ANNULER_RESERVATION (
        p_id_navire IN NUMBER,
        p_id_reservation IN NUMBER
    ) IS
        v_statut VARCHAR2(50);
        v_proprietaire NUMBER;
    BEGIN
        -- Vérification existence et propriété
        BEGIN
            SELECT statut, id_navire INTO v_statut, v_proprietaire
            FROM RESERVATION WHERE id_reservation = p_id_reservation;
            
            IF v_proprietaire != p_id_navire THEN
                RAISE_APPLICATION_ERROR(-20043, 'Sécurité : Cette réservation ne vous appartient pas.');
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20043, 'Réservation introuvable.');
        END;

        -- Vérification statut (On ne peut annuler que ce qui est encore en attente)
        IF UPPER(v_statut) != 'En attente' THEN
            RAISE_APPLICATION_ERROR(-20042, 'Impossible d''annuler : La demande a déjà été traitée par le port ou annulée.');
        END IF;

        -- Action : Annulation
        UPDATE RESERVATION SET statut = 'Annulee Client' WHERE id_reservation = p_id_reservation;
        COMMIT;
    END ANNULER_RESERVATION;    


END PKG_CLIENT;
/

-- Droit de connexion
GRANT CONNECT TO ROLE_CLIENT;

-- Droit d'exécuter le package
GRANT EXECUTE ON PKG_CLIENT TO ROLE_CLIENT;
