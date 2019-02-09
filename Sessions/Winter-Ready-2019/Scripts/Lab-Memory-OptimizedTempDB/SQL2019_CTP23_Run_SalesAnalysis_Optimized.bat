ECHO OFF
rd /s /q %temp%\output
"ostress.exe" -E -S.\SQL2019_CTP23 -dAdventureWorks -Q"EXEC dbo.usp_SalesAnalysis_Optimized" -mstress -quiet -n1 -r1 | FINDSTR "Cantfindthisstring"
rd /s /q %temp%\output
"ostress.exe" -E -S.\SQL2019_CTP23 -dAdventureWorks -Q"EXEC dbo.usp_SalesAnalysis_Optimized" -mstress -quiet -n100 -r300 | FINDSTR "QEXEC Starting Creating elapsed"