-- Test de Mise à jour Salaire (Succès)
-- On récupère l'ID du nouvel employé
DECLARE
    v_id NUMBER;
BEGIN
    SELECT MAX(id_employe) INTO v_id FROM EMPLOYE;
    PKG_RH.MAJ_SALAIRE(v_id, 70.00);
END;
/


-- Test Négatif : Salaire invalide (echec)
BEGIN
    PKG_RH.MAJ_SALAIRE(1, -50);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('SUCCES TEST NEGATIF: ' || SQLERRM);
END;
/


-- Test Consultation : Vérifier si l'employé est en surcharge
DECLARE
    v_statut VARCHAR2(20);
BEGIN
    -- Test sur l'employé 21 qui a travaillé dans le jeu de données
    v_statut := PKG_RH.EST_SURCHARGE(21);
    DBMS_OUTPUT.PUT_LINE('Statut surcharge employé 21 : ' || v_statut);
END;
/

-- Test de Recrutement (Succès)
BEGIN
    PKG_RH.RECRUTER_EMPLOYE(
        p_matricule => 'TEST-RH-02',  
        p_nom => 'MARTIN',            
        p_prenom => 'Sophie',
        p_poste => 'Docker', 
        p_taux_horaire => 65.00, 
        p_email => 's.martin@test.ma', 
        p_id_superieur => 2
    );
END;
/
