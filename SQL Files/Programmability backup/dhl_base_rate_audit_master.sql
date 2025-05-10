



USE [TNL_RATING]
GO
/****** Object:  StoredProcedure [dbo].[dhl_base_rate_audit_master_2]    Script Date: 7/16/2024 4:04:43 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************************************************************************

   Description:  dhl_base_rate_audit_master_2

exec [tnl_rating].[dbo].[dhl_base_rate_audit_master_2] 541947
exec [tnl_rating].[dbo].[dhl_base_rate_audit_master_2] 586297

***********************************************************************************************************/
ALTER PROCEDURE [dbo].[dhl_base_rate_audit_master] @ywControlno AS INT
AS
SET NOCOUNT ON;

BEGIN
    DELETE FROM tnl_rating.dbo.dhl_base_rate_audit 
    WHERE [ControlNo] = @ywControlno;

    INSERT INTO tnl_rating.dbo.dhl_base_rate_audit
    SELECT 
        a.ChildID,
        a.ControlNo,
        b.AccountNo,
        b.InvoiceDate,
        a.InvoiceNo,
        a.TrackingNo,
        b.Pickup_DTTM,
        b.Currency,
        b.SenderStateProv,
        b.SenderCountryCode,
        b.ReceiverStateProv,
        b.ReceiverCountryCode,
        a.ServiceTypeCode,
        b.Zone,
        ISNULL(b.ChargeableWeight, b.BilledWeight),
        b.BilledWeightUOM,
        a.ChargeCode,
        a.ChargeAmt,
        '' AS 'Origin Zone',
        '' AS 'Destination Zone',
        '' AS 'Pricing Zone',
        NULL AS 'ContractRate',
        NULL AS 'PotentialError'
    FROM tnl_dhl.dbo.dhl_ebill_lineitem a
    LEFT JOIN tnl_dhl.dbo.dhl_ebill_package b 
        ON a.ControlNo = b.ControlNo AND a.TrackingNo = b.TrackingNo 
    WHERE a.ControlNo = @ywControlno
    AND a.ChargeCode = 'FREIGHT AMT';

    UPDATE tnl_rating.dbo.dhl_base_rate_audit 
    SET [ContractRate] = CASE 
        WHEN rates.RateType IN ('Flat LB','Flat','Flat KG') THEN rates.Rate 
        WHEN rates.RateType = 'Per LB (M)' THEN a.BilledWeight * rates.Rate
        WHEN rates.RateType = 'Per0.5KG_A' THEN rates.BaseRateForMultiplier + (a.BilledWeight - rates.MinWeight) * 2 * rates.Rate
        WHEN rates.RateType = 'Per1.0KG_A' THEN rates.BaseRateForMultiplier + (CEILING(a.BilledWeight) - rates.MinWeight) * rates.Rate
        WHEN rates.RateType = 'Per0.5KG_M' THEN a.BilledWeight * 2 * rates.Rate
        ELSE NULL 
    END 

 FROM 
        tnl_rating.dbo.dhl_base_rate_audit a
    LEFT JOIN 
        tnl_reporting.dbo.Warehouse_Dictionary svccodes
        ON svccodes.Carrier = 'DHL'
        AND CASE 
            WHEN a.ServiceTypeCode IN ('CX','PN','IE') THEN 'CX' 
            ELSE a.ServiceTypeCode 
        END = svccodes.Code
        AND svccodes.Category = 'ServiceType'
    LEFT JOIN 
        tnl_reporting.dbo.company_child ChildIDTable 
        ON a.ChildID = ChildIDTable.ChildID

  LEFT JOIN tnl_rating.dbo.dhl_country_zoning_table orig_country 
        ON a.ChildID = orig_country.ChildID 
        AND CASE 
            WHEN a.Currency = 'USD' THEN 'US' 
            ELSE ChildIDTable.CompanyChildCountry 
        END = orig_country.RateCountry
        AND CASE 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode = 'US' THEN 
                CASE 
                    WHEN a.ReceiverCountryCode IN ('AS','GU','MH','FM','MP','PW','PR','US','VI') THEN 'Territory' 
                    ELSE 'Export' 
                END
            WHEN a.Currency = 'USD' AND a.ReceiverCountryCode = 'US' THEN 'Import' 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom3C'
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode != a.ReceiverCountryCode THEN '3C'
            WHEN ChildIDTable.CompanyChildCountry = a.SenderCountryCode THEN 'Export'
            WHEN ChildIDTable.CompanyChildCountry = a.ReceiverCountryCode THEN 'Import'
            WHEN ChildIDTable.CompanyChildCountry != a.SenderCountryCode AND ChildIDTable.CompanyChildCountry != a.ReceiverCountryCode THEN '3C'
			WHEN a.SenderCountryCode != 'DE' AND a.ReceiverCountryCode != 'DE' AND a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom3C' ---- added by rd 
            ELSE NULL 
        END = orig_country.ImportExport
        AND CASE 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode = 'US' THEN a.SenderCountryCode
            WHEN a.Currency = 'USD' AND a.ReceiverCountryCode = 'US' THEN a.SenderCountryCode 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode = a.ReceiverCountryCode THEN a.SenderCountryCode
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode != a.ReceiverCountryCode THEN a.SenderCountryCode
            WHEN ChildIDTable.CompanyChildCountry = a.SenderCountryCode THEN a.ReceiverCountryCode
            ELSE NULL 
        END = orig_country.TargetCountry
   
   
   --------------------------------------------------------------------------------------------------------------------------------------------------------
   
   LEFT JOIN tnl_rating.dbo.dhl_country_zoning_table dest_country 
        ON a.ChildID = dest_country.ChildID 
        AND CASE 
            WHEN a.Currency = 'USD' THEN 'US' 
            ELSE ChildIDTable.CompanyChildCountry 
        END = dest_country.RateCountry
        AND CASE 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode = 'US' THEN 
                CASE 
                    WHEN a.ReceiverCountryCode IN ('AS','GU','MH','FM','MP','PW','PR','US','VI') THEN 'Territory' 
                    ELSE 'Export' 
                END
            WHEN a.Currency = 'USD' AND a.ReceiverCountryCode = 'US' THEN 'Import' 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom3C'
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode != a.ReceiverCountryCode THEN '3C'
            WHEN ChildIDTable.CompanyChildCountry = a.SenderCountryCode THEN 'Export'
            WHEN ChildIDTable.CompanyChildCountry = a.ReceiverCountryCode THEN 'Import'
            WHEN ChildIDTable.CompanyChildCountry != a.SenderCountryCode AND ChildIDTable.CompanyChildCountry != a.ReceiverCountryCode THEN '3C'
			WHEN a.SenderCountryCode != 'DE' AND a.ReceiverCountryCode != 'DE' AND a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom3C' ---- added by rd 
            ELSE NULL 
        END = dest_country.ImportExport
        AND CASE 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode = 'US' THEN a.ReceiverCountryCode 
            WHEN a.Currency = 'USD' AND a.ReceiverCountryCode = 'US' THEN a.ReceiverCountryCode 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode = a.ReceiverCountryCode THEN a.ReceiverCountryCode
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode != a.ReceiverCountryCode THEN a.ReceiverCountryCode
            WHEN ChildIDTable.CompanyChildCountry = a.SenderCountryCode THEN a.ReceiverCountryCode
            ELSE NULL 
        END = dest_country.TargetCountry
    



--------------------------------------------------------------------------------------------------------------------------------------------------------
	


	LEFT JOIN tnl_rating.dbo.dhl_zone_conversion_matrix c
        ON a.ChildID = c.ChildID
        AND c.LocalZone = CASE 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode = 'US' THEN 
                CASE 
                    WHEN a.ReceiverCountryCode IN ('AS','GU','MH','FM','MP','PW','PR','US','VI') THEN orig_country.Zone 
                    ELSE '1' 
                END
            WHEN a.Currency = 'USD' AND a.ReceiverCountryCode = 'US' THEN '1' 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode = a.ReceiverCountryCode THEN orig_country.Zone
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode != a.ReceiverCountryCode THEN orig_country.Zone
            WHEN ChildIDTable.CompanyChildCountry = a.SenderCountryCode THEN orig_country.Zone
            ELSE NULL 
        END
        AND c.InternationalZone = CASE
            WHEN a.Currency = 'USD' AND a.SenderCountryCode = 'US' THEN 
                CASE 
                    WHEN a.ReceiverCountryCode IN ('AS','GU','MH','FM','MP','PW','PR','US','VI') THEN dest_country.Zone 
                    ELSE dest_country.Zone 
                END
            WHEN a.Currency = 'USD' AND a.ReceiverCountryCode = 'US' THEN orig_country.Zone 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode = a.ReceiverCountryCode THEN dest_country.Zone
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode != a.ReceiverCountryCode THEN dest_country.Zone
            WHEN ChildIDTable.CompanyChildCountry = a.SenderCountryCode THEN dest_country.Zone
            ELSE NULL 
        END
        AND CASE 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode = 'US' THEN 
                CASE 
                    WHEN a.ReceiverCountryCode IN ('AS','GU','MH','FM','MP','PW','PR','US','VI') THEN 'Territory' 
                    ELSE 'Export' 
                END
            WHEN a.Currency = 'USD' AND a.ReceiverCountryCode = 'US' THEN 'Import' 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom3C'
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode != a.ReceiverCountryCode THEN '3C'
            WHEN ChildIDTable.CompanyChildCountry = a.SenderCountryCode THEN 'Export'
            WHEN ChildIDTable.CompanyChildCountry = a.ReceiverCountryCode THEN 'Import'
            WHEN ChildIDTable.CompanyChildCountry != a.SenderCountryCode AND ChildIDTable.CompanyChildCountry != a.ReceiverCountryCode THEN '3C'
			WHEN a.SenderCountryCode != 'DE' AND a.ReceiverCountryCode != 'DE' AND a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom3C' ---- added by rd 
            ELSE NULL 
        END = c.ImportExport


  ----------------------------------------------------------------------------  
	
	LEFT JOIN tnl_rating.dbo.dhl_express_rate_master rates
        ON a.ChildID = rates.ChildID 
        AND CASE 
            WHEN a.Currency = 'USD' AND a.SenderCountryCode = 'US' THEN 
                CASE 
                    WHEN a.ReceiverCountryCode IN ('AS','GU','MH','FM','MP','PW','PR','US','VI') THEN 'Territory' 
                    ELSE 'Export' 
                END
            WHEN a.Currency = 'USD' AND a.ReceiverCountryCode = 'US' THEN 'Import' 
            WHEN a.SenderCountryCode != a.ReceiverCountryCode AND a.ReceiverCountryCode = ChildIDTable.CompanyChildCountry THEN 'Import'
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom3C'
            WHEN a.Currency = 'USD' AND a.SenderCountryCode != 'US' AND a.ReceiverCountryCode != 'US' AND a.SenderCountryCode != a.ReceiverCountryCode THEN '3C'
            WHEN a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom'
            WHEN ChildIDTable.CompanyChildCountry = a.SenderCountryCode THEN 'Export'
            WHEN ChildIDTable.CompanyChildCountry = a.ReceiverCountryCode THEN 'Import'
            WHEN ChildIDTable.CompanyChildCountry != a.SenderCountryCode AND ChildIDTable.CompanyChildCountry != a.ReceiverCountryCode THEN '3C'
			WHEN a.SenderCountryCode != 'DE' AND a.ReceiverCountryCode != 'DE' AND a.SenderCountryCode = a.ReceiverCountryCode THEN 'Dom3C' ---- added by rd 
            ELSE NULL 
        END = rates.ExportImport
        AND svccodes.CodeDesc = rates.Service
        --AND COALESCE(c.Ratezone, 'NULL') = COALESCE(rates.Zone, 'NULL')
		AND c.Ratezone=rates.Zone
        AND a.BilledWeight > rates.minWeight
        AND a.BilledWeight <= rates.maxWeight
   
   
--   --------------------------------------------------------------------------------------------------------------------------------------------------------
   

    WHERE ControlNo = @ywControlno;
    UPDATE tnl_rating.dbo.dhl_base_rate_audit 
    SET PotentialError = ROUND([ChargeAmt] - [ContractRate], 2) 
    WHERE ControlNo = @ywControlno;
END
