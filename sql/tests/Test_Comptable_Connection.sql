-- Calculer le coût d'une escale (Test fonction de calcul)
DECLARE
    v_cout NUMBER;
BEGIN
    -- Escale 500 (CMA CGM) a des opérations dans le DML
    v_cout := PKG_FINANCE.CALCULER_COUT_TOTAL_ESCALE(500);
    DBMS_OUTPUT.PUT_LINE('Coût total calculé pour escale 500 : ' || v_cout);
END;
/


-- Créer une facture pour cette escale
BEGIN
    PKG_FINANCE.CREER_FACTURE(
        p_montant => 50000, -- Montant arbitraire ou basé sur le calcul précédent
        p_date_echeance => SYSTIMESTAMP + 30,
        p_id_escale => 500
    );
END;
/

-- Payer une facture deja reglee
DECLARE
    v_id_facture NUMBER;
BEGIN
    SELECT MAX(id_facture) INTO v_id_facture FROM FACTURE WHERE id_escale = 500;
    
    PKG_FINANCE.PAYER_FACTURE(v_id_facture);
    DBMS_OUTPUT.PUT_LINE('Facture payée : ' || v_id_facture);
END;
/


-- Test Trigger Audit : Essayer de supprimer une facture payée (echec)
DECLARE
    v_id_facture NUMBER;
BEGIN
    SELECT MAX(id_facture) INTO v_id_facture FROM FACTURE WHERE statut_paiement = 'Payee';
    
    DELETE FROM FACTURE WHERE id_facture = v_id_facture;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('SUCCES TEST SECURITE COMPTABLE: ' || SQLERRM);
END;
/

-- Test à exécuter en tant que U_COMPTABLE
DECLARE
    v_id_facture NUMBER;
BEGIN
    SELECT MAX(id_facture) INTO v_id_facture FROM FACTURE WHERE statut_paiement = 'Payee';
    
    -- Tentative de suppression directe
    DELETE FROM FACTURE WHERE id_facture = v_id_facture;

EXCEPTION
    WHEN OTHERS THEN
        -- On vérifie le code erreur exact
        IF SQLCODE = -1031 THEN
             DBMS_OUTPUT.PUT_LINE('SUCCES TEST DROITS : L''utilisateur n''a pas le privilège DELETE (ORA-01031).');
        ELSIF SQLCODE = -20014 THEN
             DBMS_OUTPUT.PUT_LINE('SUCCES TEST TRIGGER : Le trigger a bloqué la facture payée.');
        ELSE
             DBMS_OUTPUT.PUT_LINE('ECHEC : Erreur inattendue -> ' || SQLERRM);
        END IF;
END;
/