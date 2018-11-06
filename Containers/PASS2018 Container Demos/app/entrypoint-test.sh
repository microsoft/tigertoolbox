#wait for the SQL Server to come up
echo "waiting for SQL Server to start up"
sleep 20s

echo "running tests"
go test -v