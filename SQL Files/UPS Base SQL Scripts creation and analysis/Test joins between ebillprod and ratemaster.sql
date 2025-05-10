



WITH cte AS (
    SELECT DISTINCT  
        p.[Lead Shipment Number],
        p.[Charge Description],
        p.ControlNo,
        p.ChildID,
        p.InvoiceDt,
        p.[Billed Weight],
        p.[Billed Weight Unit of Measure],
        p.[Container Type],
        p.Zone,
        p.[Transaction Date],
        r.Notes,p.[Package Quantity],
        r.PackageCode,
        p.[Net Amount],
        r.Rate,
        ROUND(
    (p.[Net Amount] - 
        CASE 
            WHEN r.Notes = 'Per LB' THEN p.[Billed Weight] * r.Rate 
            ELSE r.Rate 
        END
    ), 2
) AS PotentialError
    FROM TestDB.dbo.ups_ebill_prod p
    LEFT JOIN TestDB.dbo.ups_rate_master r
        ON p.[Charge Description] = r.ServiceTypeDescription
        AND TRY_CAST(p.Zone AS INT) = TRY_CAST(r.Zone AS INT)
        AND FLOOR(p.[Billed Weight]) BETWEEN r.MinWeight AND r.MaxWeight
        AND p.[Billed Weight Unit of Measure] = r.WtUnit
        AND p.[Container Type] = r.PackageCode
        AND p.[Transaction Date] BETWEEN r.EffectiveDate AND r.ExpirationDate
        AND p.ChildID = r.ChildID
)

SELECT *
FROM cte 
where controlno = 1006
and PotentialError<>0
ORDER BY PotentialError DESC

--SELECT FORMAT(SUM(ABS(PotentialError)), 'C') AS TotalPotentialError FROM cte;



