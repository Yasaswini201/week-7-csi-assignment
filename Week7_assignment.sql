-- =============================================
-- Table Definitions
-- =============================================

IF OBJECT_ID('dbo.Customer', 'U') IS NOT NULL DROP TABLE dbo.Customer;
CREATE TABLE dbo.Customer (
    CustomerID     INT            NOT NULL PRIMARY KEY,
    CustomerName   NVARCHAR(100)  NULL,
    Address        NVARCHAR(200)  NULL,
    City           NVARCHAR(100)  NULL,
    PreviousCity   NVARCHAR(100)  NULL,       -- for SCD Type 3 / Type 6
    StartDate      DATETIME       NULL,       -- for SCD Type 2 / Type 6
    EndDate        DATETIME       NULL,       -- for SCD Type 2 / Type 6
    IsCurrent      BIT            NULL        -- for SCD Type 2 / Type 6
);
GO

IF OBJECT_ID('dbo.Customer_History', 'U') IS NOT NULL DROP TABLE dbo.Customer_History;
CREATE TABLE dbo.Customer_History (
    HistoryID      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerID     INT                NOT NULL,
    CustomerName   NVARCHAR(100)      NULL,
    Address        NVARCHAR(200)      NULL,
    City           NVARCHAR(100)      NULL,
    ChangeDate     DATETIME           NOT NULL DEFAULT GETDATE()
);
GO


-- =============================================
-- SCD Type 0: Fixed Attribute (no updates)
-- =============================================
CREATE PROCEDURE dbo.sp_SCD0_Update
    @CustomerID   INT,
    @CustomerName NVARCHAR(100),
    @Address      NVARCHAR(200),
    @City         NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        INSERT INTO dbo.Customer (CustomerID, CustomerName, Address, City)
        VALUES (@CustomerID, @CustomerName, @Address, @City);
    END
END
GO


-- =============================================
-- SCD Type 1: Overwrite (no history)
-- =============================================
CREATE PROCEDURE dbo.sp_SCD1_Update
    @CustomerID   INT,
    @CustomerName NVARCHAR(100),
    @Address      NVARCHAR(200),
    @City         NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        UPDATE dbo.Customer
        SET CustomerName = @CustomerName,
            Address      = @Address,
            City         = @City
        WHERE CustomerID = @CustomerID;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.Customer (CustomerID, CustomerName, Address, City)
        VALUES (@CustomerID, @CustomerName, @Address, @City);
    END
END
GO


-- =============================================
-- SCD Type 2: Versioning (preserve history)
-- =============================================
CREATE PROCEDURE dbo.sp_SCD2_Update
    @CustomerID   INT,
    @CustomerName NVARCHAR(100),
    @Address      NVARCHAR(200),
    @City         NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME = GETDATE();

    IF EXISTS (
        SELECT 1 FROM dbo.Customer
        WHERE CustomerID = @CustomerID
          AND IsCurrent = 1
          AND (CustomerName <> @CustomerName OR Address <> @Address OR City <> @City)
    )
    BEGIN
        -- expire old version
        UPDATE dbo.Customer
        SET EndDate   = @Now,
            IsCurrent = 0
        WHERE CustomerID = @CustomerID AND IsCurrent = 1;

        -- insert new version
        INSERT INTO dbo.Customer
            (CustomerID, CustomerName, Address, City, StartDate, EndDate, IsCurrent)
        VALUES
            (@CustomerID, @CustomerName, @Address, @City, @Now, NULL, 1);
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        INSERT INTO dbo.Customer
            (CustomerID, CustomerName, Address, City, StartDate, EndDate, IsCurrent)
        VALUES
            (@CustomerID, @CustomerName, @Address, @City, @Now, NULL, 1);
    END
END
GO


-- =============================================
-- SCD Type 3: Current + Previous attribute
-- =============================================
CREATE PROCEDURE dbo.sp_SCD3_Update
    @CustomerID   INT,
    @City         NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM dbo.Customer
        WHERE CustomerID = @CustomerID AND City <> @City
    )
    BEGIN
        UPDATE dbo.Customer
        SET PreviousCity = City,
            City         = @City
        WHERE CustomerID = @CustomerID;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        INSERT INTO dbo.Customer (CustomerID, City, PreviousCity)
        VALUES (@CustomerID, @City, NULL);
    END
END
GO


-- =============================================
-- SCD Type 4: History in separate table
-- =============================================
CREATE PROCEDURE dbo.sp_SCD4_Update
    @CustomerID   INT,
    @CustomerName NVARCHAR(100),
    @Address      NVARCHAR(200),
    @City         NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 FROM dbo.Customer
        WHERE CustomerID = @CustomerID
          AND (CustomerName <> @CustomerName OR Address <> @Address OR City <> @City)
    )
    BEGIN
        -- archive old record
        INSERT INTO dbo.Customer_History (CustomerID, CustomerName, Address, City)
        SELECT CustomerID, CustomerName, Address, City
        FROM dbo.Customer
        WHERE CustomerID = @CustomerID;

        -- update current
        UPDATE dbo.Customer
        SET CustomerName = @CustomerName,
            Address      = @Address,
            City         = @City
        WHERE CustomerID = @CustomerID;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        INSERT INTO dbo.Customer (CustomerID, CustomerName, Address, City)
        VALUES (@CustomerID, @CustomerName, @Address, @City);
    END
END
GO


-- =============================================
-- SCD Type 6: Hybrid (Type 1 + Type 2 + Type 3)
-- =============================================
CREATE PROCEDURE dbo.sp_SCD6_Update
    @CustomerID   INT,
    @CustomerName NVARCHAR(100),
    @Address      NVARCHAR(200),
    @City         NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now     DATETIME = GETDATE();
    DECLARE @OldCity NVARCHAR(100);

    IF EXISTS (
        SELECT 1 FROM dbo.Customer
        WHERE CustomerID = @CustomerID AND IsCurrent = 1
          AND (CustomerName <> @CustomerName OR Address <> @Address OR City <> @City)
    )
    BEGIN
        -- expire old
        UPDATE dbo.Customer
        SET EndDate   = @Now,
            IsCurrent = 0
        WHERE CustomerID = @CustomerID AND IsCurrent = 1;

        -- get previous city
        SELECT @OldCity = City
        FROM dbo.Customer
        WHERE CustomerID = @CustomerID AND IsCurrent = 0;

        -- insert new record
        INSERT INTO dbo.Customer
            (CustomerID, CustomerName, Address, City, PreviousCity, StartDate, EndDate, IsCurrent)
        VALUES
            (@CustomerID, @CustomerName, @Address, @City, @OldCity, @Now, NULL, 1);
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        INSERT INTO dbo.Customer
            (CustomerID, CustomerName, Address, City, PreviousCity, StartDate, EndDate, IsCurrent)
        VALUES
            (@CustomerID, @CustomerName, @Address, @City, NULL, @Now, NULL, 1);
    END
END
GO
