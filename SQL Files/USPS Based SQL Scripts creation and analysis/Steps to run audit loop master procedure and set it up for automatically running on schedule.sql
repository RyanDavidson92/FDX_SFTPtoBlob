
--- This command below will execute EVERY SPROC in one command. in order to get this fully operational i will need to setup a sql server agent and add a job to run this every week. 
EXEC dbo.base_rate_audit_loop_master;

--- Just for fun, wipe everything from the target table and re-run the loop master command to prove the loop master works. Everything goes back to where it was. 
---delete from usps_base_rate_audit

select * from usps_base_rate_audit

CREATE PROCEDURE dbo.base_rate_audit_loop_master
AS
BEGIN
    SET NOCOUNT ON;

    -- Optional tracking/logging
    DECLARE @masterName VARCHAR(100) = 'base_rate_audit_loop_master';
    EXEC dbo.all_base_rate_audit_loop_tracking @masterName, 'start';

    -- USPS Audit Loop
    EXEC dbo.USPS_base_rate_audit_loop;

    -- Add more carrier audits here in the future
    -- EXEC dbo.UPS_base_rate_audit_loop;
    -- EXEC dbo.FEDEX_base_rate_audit_loop;

    -- Optional end tracking/logging
    EXEC dbo.all_base_rate_audit_loop_tracking @masterName, 'end';
END;
