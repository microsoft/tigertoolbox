USE rest_api_example
GO 

INSERT INTO users(firstName, lastName, phoneNumber, email, nextFlight, previousFlight) VALUES ('Vera', 'Yu',4759997676,'vera@msft.com','AC989','JAL01')
INSERT INTO users(firstName, lastName, phoneNumber, email, nextFlight, previousFlight) VALUES ('Poonam','Thiara',9999816212,'bob@cool.com','BC87','AC1212')
SELECT firstName, lastName, cast(memberID as nvarchar(50)), phoneNumber, email, nextFlight, previousFlight FROM users

GO
