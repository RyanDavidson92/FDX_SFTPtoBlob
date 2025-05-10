

------- Create loop tracking support table for stored procedure loop


ALTER PROCEDURE dbo.all_base_rate_audit_loop_tracking
    @AuditName VARCHAR(100),
    @ActionType VARCHAR(10) -- 'start' or 'end'
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_NAME = 'base_rate_audit_loop_tracking'
    )
    BEGIN
        CREATE TABLE dbo.base_rate_audit_loop_tracking (
            AuditID INT IDENTITY(1,1) PRIMARY KEY,
            AuditName VARCHAR(100),
            ActionType VARCHAR(10),
            ActionTime DATETIME DEFAULT GETDATE()
        );
    END

    INSERT INTO dbo.base_rate_audit_loop_tracking (AuditName, ActionType)
    VALUES (@AuditName, @ActionType);
END;
