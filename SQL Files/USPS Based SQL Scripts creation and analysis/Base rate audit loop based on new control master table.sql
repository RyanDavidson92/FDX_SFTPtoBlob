SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[USPS_base_rate_audit_loop]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @controlno INT;
    DECLARE @status VARCHAR(100);
    DECLARE @AuditName VARCHAR(100) = 'USPS_base_rate_audit_loop';

    EXEC all_base_rate_audit_loop_tracking @AuditName, 'start';

    -- Temp table setup
    IF OBJECT_ID('tempdb..#tempControlNoUSPSAudit') IS NOT NULL DROP TABLE #tempControlNoUSPSAudit;
    CREATE TABLE #tempControlNoUSPSAudit (ControlNo INT);

    /* Add controlnos that need to be audited.
       This looks at USPS child IDs with a NULL ContractRate, meaning they haven't been audited yet.
       It only looks at controlnos from the last 8 weeks. */

    INSERT INTO #tempControlNoUSPSAudit (ControlNo)
    SELECT DISTINCT cm.ControlNo
    FROM TestDB.dbo.control_master cm
    WHERE cm.LoadTimestamp >= DATEADD(WEEK, -8, GETDATE())
      AND cm.ControlNo NOT IN (
          SELECT ControlNo 
          FROM TestDB.dbo.usps_base_rate_audit
          GROUP BY ControlNo
      );

    DECLARE rc CURSOR FOR
    SELECT ControlNo FROM #tempControlNoUSPSAudit;

    OPEN rc;
    FETCH NEXT FROM rc INTO @controlno;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @status = 'Processing USPS controlno ' + CAST(@controlno AS VARCHAR(50));
        RAISERROR(@status, 0, 1) WITH NOWAIT;

        EXEC dbo.USPS_base_rate_audit_master @ywControlno = @controlno;

        INSERT INTO TestDB.dbo.tnl_statistics (
            carrier, appname, appfunction, trancount
        )
        VALUES (
            'USPS', 'USPS base rate audit', '', 1
        );

        FETCH NEXT FROM rc INTO @controlno;
    END;

    CLOSE rc;
    DEALLOCATE rc;

    EXEC all_base_rate_audit_loop_tracking @AuditName, 'end';
END;
GO
