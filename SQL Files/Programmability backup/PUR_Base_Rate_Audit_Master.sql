



ALTER PROCEDURE [dbo].[pur_base_rate_audit_master] @ywControlNo AS INT
AS
SET NOCOUNT ON;

BEGIN
	/* set the contract net rate amounts for shipments LESS THAN OR EQUAL TO 150 LBS */
	UPDATE tnl_rating.dbo.pur_base_rate_audit
	SET [Contractual_rate] = b.[Rate]
	FROM tnl_rating.dbo.pur_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.pur_rate_master b ON a.ChildID = b.ChildID
		AND cast(InvoiceDT AS DATETIME) >= b.EffectiveDate
		AND cast(InvoiceDT AS DATETIME) <= b.ExpirationDate
		AND a.[ACTUAL_PRODUCT_NUM] = b.[DECLARED_PRODUCT_NUM]
		AND --service code matches
		a.[Rate_Code] = b.[Rate_Code]
		AND -- zone matches
		cast(a.[WGT_ROUNDED] AS FLOAT) >= b.MinWeight
		AND --weight matches
		cast(a.[WGT_ROUNDED] AS FLOAT) <= b.MaxWeight
	WHERE controlno = @ywControlNo
		AND b.ChildId = a.ChildID
		AND a.[WGT_ROUNDED] <= 150

	/* set the contract net rate amounts for shipments OVER 150 LBS. First set the rate to the 150lb rate, then for every lb above 150 lbs, add the per lb rate. For example,
   if the weight was 174lbs, and if the 150lb rate was $43.00 and the per-pound rate above that was .2971/lb, then the rate is $43.00 + (24 x .2971) = $50.13 */
	UPDATE tnl_rating.dbo.pur_base_rate_audit
	SET [Contractual_rate] = b.[Rate]
	FROM tnl_rating.dbo.pur_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.pur_rate_master b ON a.ChildID = b.ChildID
		AND cast(InvoiceDT AS DATETIME) >= b.EffectiveDate
		AND cast(InvoiceDT AS DATETIME) <= b.ExpirationDate
		AND a.[ACTUAL_PRODUCT_NUM] = b.[DECLARED_PRODUCT_NUM]
		AND --service code matches
		a.[Rate_Code] = b.[Rate_Code]
		AND -- zone matches
		b.MinWeight = 150
	WHERE controlno = @ywControlNo
		AND b.ChildId = a.ChildID
		AND a.[WGT_ROUNDED] > 150

	UPDATE tnl_rating.dbo.pur_base_rate_audit
	SET [Contractual_rate] = round([Contractual_rate] + ([Rate] * (cast(a.[WGT_ROUNDED] AS FLOAT) - 150)), 2) --add the multiplier for every lb above 150lbs
	FROM tnl_rating.dbo.pur_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.pur_rate_master b ON a.ChildID = b.ChildID
		AND cast(InvoiceDT AS DATETIME) >= b.EffectiveDate
		AND cast(InvoiceDT AS DATETIME) <= b.ExpirationDate
		AND a.[ACTUAL_PRODUCT_NUM] = b.[DECLARED_PRODUCT_NUM]
		AND --service code matches
		a.[Rate_Code] = b.[Rate_Code]
		AND -- zone matches
		cast(a.[WGT_ROUNDED] AS FLOAT) >= b.MinWeight
		AND --weight matches
		cast(a.[WGT_ROUNDED] AS FLOAT) <= b.MaxWeight
	WHERE controlno = @ywControlNo
		AND b.ChildId = a.ChildID
		AND a.[WGT_ROUNDED] > 150




/***************************************************************************************************************************************************************************************
	Purolator has been putting incorrect sold to contracts in the new invoices (apr 2024 format change). This code below is a temporary stop-gap measure
	put in place to be able to audit clients by account number while Purolator figures out their mistake.

	The first client to be put through this is Groupe Dynamite, ChildID = 11226
	For Groupe Dynamite, account number 4896120 should get rates for sold-to_contract # 0009802064. All other accounts should get contract # 0009801431
****************************************************************************************************************************************************************************************/

	/* set the contract net rate amounts for shipments LESS THAN OR EQUAL TO 150 LBS */
	UPDATE tnl_rating.dbo.pur_base_rate_audit
	SET [Contractual_rate] = b.[Rate]
	FROM tnl_rating.dbo.pur_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.pur_rate_master b ON a.ChildID = b.ChildID
		AND cast(InvoiceDT AS DATETIME) >= b.EffectiveDate
		AND cast(InvoiceDT AS DATETIME) <= b.ExpirationDate
		AND a.[ACTUAL_PRODUCT_NUM] = b.[DECLARED_PRODUCT_NUM]
		AND --service code matches
		a.[Rate_Code] = b.[Rate_Code]
		AND -- zone matches
		cast(a.[WGT_ROUNDED] AS FLOAT) >= b.MinWeight
		AND --weight matches
		cast(a.[WGT_ROUNDED] AS FLOAT) <= b.MaxWeight
	WHERE controlno = @ywControlNo
		AND b.ChildId = a.ChildID
		AND a.[WGT_ROUNDED] <= 150
		AND a.ChildID = 11226 --ChildID 11226 is Groupe Dynamite

	/* set the contract net rate amounts for shipments OVER 150 LBS. First set the rate to the 150lb rate, then for every lb above 150 lbs, add the per lb rate. For example,
   if the weight was 174lbs, and if the 150lb rate was $43.00 and the per-pound rate above that was .2971/lb, then the rate is $43.00 + (24 x .2971) = $50.13 */
	UPDATE tnl_rating.dbo.pur_base_rate_audit
	SET [Contractual_rate] = b.[Rate]
	FROM tnl_rating.dbo.pur_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.pur_rate_master b ON a.ChildID = b.ChildID
		AND cast(InvoiceDT AS DATETIME) >= b.EffectiveDate
		AND cast(InvoiceDT AS DATETIME) <= b.ExpirationDate
		AND a.[ACTUAL_PRODUCT_NUM] = b.[DECLARED_PRODUCT_NUM]
		AND --service code matches
		a.[Rate_Code] = b.[Rate_Code]
		AND -- zone matches
		b.MinWeight = 150
		
	WHERE controlno = @ywControlNo
		AND b.ChildId = a.ChildID
		AND a.[WGT_ROUNDED] > 150
		AND a.ChildID = 11226 --ChildID 11226 is Groupe Dynamite






------------------ Added by R.D on 3/3/25 to account for Henry Schein multipiece shipments using min net charge per piece at 9% based off list rate for shipments with pieces > 1. 

UPDATE tnl_rating.dbo.pur_base_rate_audit
SET [Contractual_rate] = CASE WHEN 
	Case when a.WGT_ROUNDED>150 and a.PIECES>1 then (ROUND(b.Rate + (b2.[Rate] * (CAST(a.[WGT_ROUNDED] AS FLOAT) - 150)), 2)) when a.WGT_ROUNDED<150 and a.PIECES>1 then b3.rate else b.Rate end > ROUND((0.09 * r.Rate) * a.PIECES, 2)
	Then (Case when a.WGT_ROUNDED>150 and a.PIECES>1 then (ROUND(b.Rate + (b2.[Rate] * (CAST(a.[WGT_ROUNDED] AS FLOAT) - 150)), 2)) when a.WGT_ROUNDED<150 and a.PIECES>1 then b3.rate else b.Rate end)
	when ROUND((0.09 * r.Rate) * a.PIECES, 2) > Case when a.WGT_ROUNDED>150 and a.PIECES>1 then (ROUND(b.Rate + (b2.[Rate] * (CAST(a.[WGT_ROUNDED] AS FLOAT) - 150)), 2)) when a.WGT_ROUNDED<150 and a.PIECES>1 then b3.rate else b.Rate end
	Then ROUND((0.09 * r.Rate) * a.PIECES, 2)
	End
FROM tnl_rating.dbo.pur_base_rate_audit a
LEFT JOIN tnl_rating.dbo.pur_rate_master b 
    ON a.ChildID = b.ChildID  -- Returns the base amount for the multiplier
    AND CAST(a.InvoiceDT AS DATETIME) BETWEEN b.EffectiveDate AND b.ExpirationDate
    AND a.[ACTUAL_PRODUCT_NUM] = b.[DECLARED_PRODUCT_NUM]
    AND a.[Rate_Code] = b.[Rate_Code]
    AND b.MinWeight = 150
LEFT JOIN tnl_rating.dbo.pur_rate_master b2 
    ON a.ChildID = b2.ChildID  -- Returns the multiplier rate for the heavy weight calculation
    AND CAST(a.InvoiceDT AS DATETIME) BETWEEN b2.EffectiveDate AND b2.ExpirationDate
    AND a.[ACTUAL_PRODUCT_NUM] = b2.[DECLARED_PRODUCT_NUM]
    AND a.[Rate_Code] = b2.[Rate_Code]
    AND b2.MinWeight = 151
LEFT JOIN tnl_rating.dbo.pur_rates_expanded r  
    ON CAST(a.InvoiceDT AS DATETIME) BETWEEN r.ShipDateEffStart AND r.ShipDateEffEnd
    AND a.[ACTUAL_PRODUCT_NUM] = r.ServiceTypeCode
    AND a.[Rate_Code] = r.Zone
    AND r.Weight = 1  -- This ensures it's using the correct weight for min net charge calculation
	LEFT JOIN tnl_rating.dbo.pur_rate_master b3 ON a.ChildID = b3.ChildID
		AND cast(PickupDT AS DATETIME) >= b3.EffectiveDate
		AND cast(PickupDT AS DATETIME) <= b3.ExpirationDate
		AND a.[ACTUAL_PRODUCT_NUM] = b3.[DECLARED_PRODUCT_NUM]
		AND --service code matches
		a.[Rate_Code] = b3.[Rate_Code]
		AND -- zone matches
		cast(a.[WGT_ROUNDED] AS FLOAT) >= b3.MinWeight
		AND --weight matches
		cast(a.[WGT_ROUNDED] AS FLOAT) <= b3.MaxWeight
WHERE a.controlno = @ywControlNo
    AND b.ChildId = a.ChildID
    AND a.ChildID = 10999 
    AND a.PIECES > 1  ---- This is only applicable to multipiece shipments 

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------









	UPDATE tnl_rating.dbo.pur_base_rate_audit
	SET [Contractual_rate] = round([Contractual_rate] + ([Rate] * (cast(a.[WGT_ROUNDED] AS FLOAT) - 150)), 2) --add the multiplier for every lb above 150lbs
	FROM tnl_rating.dbo.pur_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.pur_rate_master b ON a.ChildID = b.ChildID
		AND cast(InvoiceDT AS DATETIME) >= b.EffectiveDate
		AND cast(InvoiceDT AS DATETIME) <= b.ExpirationDate
		AND a.[ACTUAL_PRODUCT_NUM] = b.[DECLARED_PRODUCT_NUM]
		AND --service code matches
		a.[Rate_Code] = b.[Rate_Code]
		AND -- zone matches
		cast(a.[WGT_ROUNDED] AS FLOAT) >= b.MinWeight
		AND --weight matches
		cast(a.[WGT_ROUNDED] AS FLOAT) <= b.MaxWeight
	WHERE controlno = @ywControlNo
		AND b.ChildId = a.ChildID
		AND a.[WGT_ROUNDED] > 150
		AND a.ChildID = 11226 --ChildID 11226 is Groupe Dynamite

/***************************************************************************************************************************************************************************************

	Delete the code above after verifying that Purolator has fixed their error and the rate audits are operating correctly.

****************************************************************************************************************************************************************************************/





	/* set the potential error amount */
	UPDATE tnl_rating.dbo.pur_base_rate_audit
	SET [PotentialError] = round([Billed_Rate] - [Contractual_Rate], 2)
	WHERE controlno = @ywControlNo

	/* Added November 8, 2023: For heavy shipments, over 150 lbs, if the "potential error" is 1 or 2 cents, we consider that to be just a rounding error. And if the "potential error" is a negative amount, indicating a potential undercharge instead of an overcharge, and it's less than half a percent of the billed rate, then we'll ignore that too. These rules help clean up the results. */
	UPDATE tnl_rating.dbo.pur_base_rate_audit
	SET [PotentialError] = 0, [Contractual_Rate] = [Billed_Rate]
	WHERE controlno = @ywControlNo
	and convert(float,ACTUAL_WGT) > 150
	and ((PotentialError <= 0.02 and PotentialError >= 0) or (round(PotentialError / Billed_Rate,3) <= 0.000 and round(PotentialError / Billed_Rate,3) >= -0.005))

	update pur_base_rate_audit
	set israted = 1
	where controlno = @ywControlno

	EXEC [pur_base_rate_audit_summary] @ywControlNo
END
