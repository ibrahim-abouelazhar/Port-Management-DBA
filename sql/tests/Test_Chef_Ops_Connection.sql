-- Tenter de voir les salaires
SELECT * FROM EMPLOYE; 

SELECT * FROM V_EMPLOYE_OPS;

-- Enregistrer une opération sur une escale existante (ex: ID 508)
BEGIN
    PKG_OPERATIONS.ENREGISTRER_OPERATION(
        p_libelle => 'Déchargement Urgent Test',
        p_type_op => 'Manutention',
        p_id_escale => 508 -- Escale existante "En cours"
    );
END;
/

-- Affecter un employé à cette opération
DECLARE
    v_id_op NUMBER;
    v_id_emp NUMBER := 22; -- Employé 'RAHMANI' (Docker)
BEGIN
    SELECT MAX(id_operation) INTO v_id_op FROM OPERATION WHERE libelle = 'Déchargement Urgent Test';
    
    PKG_OPERATIONS.AFFECTER_EMPLOYE(
        p_id_employe => v_id_emp,
        p_id_operation => v_id_op,
        p_role => 'Manutentionnaire',
        p_heures => 4
    );
    DBMS_OUTPUT.PUT_LINE('Employé affecté.');
END;
/

-- Test Trigger : Opération avant arrivée du navire (echec)
BEGIN
    PKG_OPERATIONS.ENREGISTRER_OPERATION('Test Fail', 'Autre', 507);
END;
/