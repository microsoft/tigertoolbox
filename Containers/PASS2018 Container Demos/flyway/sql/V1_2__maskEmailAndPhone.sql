USE rest_api_example
GO

ALTER TABLE users ALTER COLUMN phoneNumber ADD MASKED WITH (FUNCTION = 'default()');  
ALTER TABLE users ALTER COLUMN email ADD MASKED WITH (FUNCTION = 'email()')