SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[base_rate_audit_loop_master]
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
GO
