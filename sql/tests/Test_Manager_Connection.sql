-- Enregistrement d'un nouveau navire (Gros Porte-Conteneurs)
BEGIN
    PKG_MANAGER_QUAI.ENREGISTRER_NAVIRE(
        p_nom => 'MEGA TESTER', 
        p_num_imo => 'IMO9999999', 
        p_pavillon => 'France',
        p_longueur => 350.0, -- Très long
        p_tirant => 15.0,    -- Profond
        p_type => 'COMMERCE',
        p_param_spe_1 => 180000, -- Tonnage
        p_param_spe_2 => '15000' -- Nb Conteneurs
    );
END;
/


-- Création d'une demande de réservation
DECLARE
    v_id_navire NUMBER;
BEGIN
    SELECT id_navire INTO v_id_navire FROM NAVIRE WHERE nom = 'MEGA TESTER';
    
    PKG_MANAGER_QUAI.CREER_RESERVATION(
        p_id_navire => v_id_navire,
        p_date_debut => SYSTIMESTAMP + 5,
        p_date_fin => SYSTIMESTAMP + 7,
        p_motif => 'Test Inaugural'
    );
END;
/

-- Planification de l'Escale (Succès : Quai 1 est profond)
DECLARE
    v_id_escale NUMBER;
    v_id_quai   NUMBER := 1; -- Quai TC1 (Prof: 18m, Long: 800m)
BEGIN
    -- On insère une escale "brouillon" manuellement car la procédure PLANIFIER fait un UPDATE
    INSERT INTO ESCALE (id_navire, statut_escale) 
    VALUES ((SELECT id_navire FROM NAVIRE WHERE nom = 'MEGA TESTER'), 'En attente')
    RETURNING id_escale INTO v_id_escale;

    PKG_MANAGER_QUAI.PLANIFIER_ESCALE(v_id_escale, v_id_quai, SYSTIMESTAMP + 5);
    DBMS_OUTPUT.PUT_LINE('Escale planifiée avec succès ID: ' || v_id_escale);
END;
/

-- Test Négatif : Planification sur un quai trop petit
DECLARE
    v_id_escale NUMBER;
BEGIN
    -- Récupérer l'escale créée ci-dessus
    SELECT MAX(id_escale) INTO v_id_escale FROM ESCALE WHERE id_navire = (SELECT id_navire FROM NAVIRE WHERE nom = 'MEGA TESTER');
    
    PKG_MANAGER_QUAI.PLANIFIER_ESCALE(v_id_escale, 3, SYSTIMESTAMP + 10);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('SUCCES TEST SECURITE PHYSIQUE: ' || SQLERRM);
END;
/