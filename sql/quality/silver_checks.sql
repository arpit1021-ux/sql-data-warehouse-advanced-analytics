/*
===============================================================================
Quality Checks: Silver Layer
===============================================================================
Every check is a query that returns the offending rows, so an empty result
means the check passed. Each check is declared with two header lines:

    -- @check    <short description>
    -- @severity error | warn

`error` checks gate the pipeline (python -m pipeline fails and the tests fail);
`warn` checks surface known source-data issues that are handled downstream.
The same file can be run by hand in any SQL client.
===============================================================================
*/

-- @check    crm_cust_info: cst_id is unique and not null
-- @severity error
SELECT cst_id, COUNT(*) AS occurrences
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL;

-- @check    crm_cust_info: names have no leading or trailing spaces
-- @severity error
SELECT cst_id, cst_firstname, cst_lastname
FROM silver.crm_cust_info
WHERE cst_firstname <> TRIM(cst_firstname)
   OR cst_lastname  <> TRIM(cst_lastname);

-- @check    crm_cust_info: marital status and gender use standard values
-- @severity error
SELECT cst_id, cst_marital_status, cst_gndr
FROM silver.crm_cust_info
WHERE cst_marital_status NOT IN ('Single', 'Married', 'n/a')
   OR cst_gndr NOT IN ('Female', 'Male', 'n/a');

-- @check    crm_prd_info: prd_id is unique and not null
-- @severity error
SELECT prd_id, COUNT(*) AS occurrences
FROM silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL;

-- @check    crm_prd_info: product names are trimmed
-- @severity error
SELECT prd_id, prd_nm
FROM silver.crm_prd_info
WHERE prd_nm <> TRIM(prd_nm);

-- @check    crm_prd_info: cost is present and not negative
-- @severity error
SELECT prd_id, prd_cost
FROM silver.crm_prd_info
WHERE prd_cost IS NULL OR prd_cost < 0;

-- @check    crm_prd_info: product line uses standard values
-- @severity error
SELECT prd_id, prd_line
FROM silver.crm_prd_info
WHERE prd_line NOT IN ('Mountain', 'Road', 'Other Sales', 'Touring', 'n/a');

-- @check    crm_prd_info: end date is not before start date
-- @severity error
SELECT prd_id, prd_start_dt, prd_end_dt
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;

-- @check    crm_prd_info: exactly one current version per product key
-- @severity error
SELECT prd_key, COUNT(*) AS current_versions
FROM silver.crm_prd_info
WHERE prd_end_dt IS NULL
GROUP BY prd_key
HAVING COUNT(*) <> 1;

-- @check    crm_sales_details: order date is not after ship or due date
-- @severity error
SELECT sls_ord_num, sls_order_dt, sls_ship_dt, sls_due_dt
FROM silver.crm_sales_details
WHERE sls_order_dt > sls_ship_dt
   OR sls_order_dt > sls_due_dt;

-- @check    crm_sales_details: sales = quantity x price, all positive
-- @severity error
SELECT sls_ord_num, sls_sales, sls_quantity, sls_price
FROM silver.crm_sales_details
WHERE sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
   OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
   OR sls_sales <> sls_quantity * sls_price;

-- @check    crm_sales_details: every line has a valid order date (invalid source dates are nulled)
-- @severity warn
SELECT sls_ord_num, sls_prd_key, sls_cust_id
FROM silver.crm_sales_details
WHERE sls_order_dt IS NULL;

-- @check    crm_sales_details: every line references a known customer and product
-- @severity error
SELECT s.sls_ord_num, s.sls_cust_id, s.sls_prd_key
FROM silver.crm_sales_details s
LEFT JOIN silver.crm_cust_info c ON s.sls_cust_id = c.cst_id
LEFT JOIN silver.crm_prd_info  p ON s.sls_prd_key = p.prd_key
WHERE c.cst_id IS NULL OR p.prd_key IS NULL;

-- @check    erp_cust_az12: birthdates are after 1924-01-01 and not in the future
-- @severity warn
SELECT cid, bdate
FROM silver.erp_cust_az12
WHERE bdate < DATE '1924-01-01' OR bdate > CURRENT_DATE;

-- @check    erp_cust_az12: gender uses standard values
-- @severity error
SELECT cid, gen
FROM silver.erp_cust_az12
WHERE gen NOT IN ('Female', 'Male', 'n/a');

-- @check    erp_loc_a101: country names are standardised (no codes or blanks)
-- @severity error
SELECT cid, cntry
FROM silver.erp_loc_a101
WHERE cntry IN ('DE', 'US', 'USA', '')
   OR cntry <> TRIM(cntry)
   OR cntry IS NULL;

-- @check    erp_px_cat_g1v2: category fields are trimmed and maintenance is Yes/No
-- @severity error
SELECT id, cat, subcat, maintenance
FROM silver.erp_px_cat_g1v2
WHERE cat <> TRIM(cat)
   OR subcat <> TRIM(subcat)
   OR maintenance NOT IN ('Yes', 'No');

-- @check    CRM customers all have an ERP demographics and location record
-- @severity error
SELECT c.cst_key
FROM silver.crm_cust_info c
LEFT JOIN silver.erp_cust_az12 d ON c.cst_key = d.cid
LEFT JOIN silver.erp_loc_a101  l ON c.cst_key = l.cid
WHERE d.cid IS NULL OR l.cid IS NULL;
