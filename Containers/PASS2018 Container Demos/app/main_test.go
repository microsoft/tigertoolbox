// main_test.go
package main
import (
	"bytes"
	"encoding/json"
    "os"
    "log"
	"testing"
	"net/http"
	"net/http/httptest"
	"fmt"
)
var a App
func TestMain(m *testing.M) {
    a = App{}
    a.Initialize("sa", "yourStrongPassw0rd!", "db", "rest_api_example")
    ensureTableExists()
    code := m.Run()
    clearTable()
    os.Exit(code)
}
func ensureTableExists() {
    if _, err := a.DB.Exec(tableCreationQuery); err != nil {
        log.Fatal(err)
    }
}
func clearTable() {
    a.DB.Exec("DELETE FROM users")
    a.DB.Exec("DBCC CHECKIDENT (users, RESEED, 0)")
}
const tableCreationQuery = `
if not exists (select * from sysobjects where name='users' and xtype='U')
create table users (
    id INT IDENTITY PRIMARY KEY,
    firstName VARCHAR(50) NOT NULL,
    lastName VARCHAR(50) NOT NULL,
    memberID UNIQUEIDENTIFIER NOT NULL DEFAULT newid(),
    phoneNumber BIGINT NOT NULL,
    email VARCHAR(50) NOT NULL,
    nextFlight VARCHAR(50) NOT NULL,
    previousFlight VARCHAR(50) NOT NULL
    )`

func TestEmptyTable(t *testing.T) {
    clearTable()
    req, _ := http.NewRequest("GET", "/users", nil)
    response := executeRequest(req)
    checkResponseCode(t, http.StatusOK, response.Code)
    if body := response.Body.String(); body != "[]" {
        t.Errorf("Expected an empty array. Got %s", body)
    }
}

func executeRequest(req *http.Request) *httptest.ResponseRecorder {
    rr := httptest.NewRecorder()
    a.Router.ServeHTTP(rr, req)

    return rr
}
func checkResponseCode(t *testing.T, expected, actual int) {
    if expected != actual {
        t.Errorf("Expected response code %d. Got %d\n", expected, actual)
    }
}

func TestGetNonExistentUser(t *testing.T){
	clearTable()

	req, _ := http.NewRequest("GET", "/user/45", nil)
	response := executeRequest(req)

	checkResponseCode(t, http.StatusNotFound, response.Code)
	var m map[string]string
    json.Unmarshal(response.Body.Bytes(), &m)
    if m["error"] != "user not found" {
        t.Errorf("Expected the 'error' key of the response to be set to 'User not found'. Got '%s'", m["error"])
    }
}

func TestCreateUser (t *testing.T){
	clearTable()
	payload := []byte(`{"firstname":"test user","lastname":"lastname","phonenumber":9989981212,"email":"bob@cool.com","previousflight":"AC1212","nextflight":"BC87"}`)

	req, _ := http.NewRequest("POST", "/user", bytes.NewBuffer(payload))
	response := executeRequest(req)
	checkResponseCode(t, http.StatusCreated, response.Code)

	var m map[string]interface{}
	json.Unmarshal(response.Body.Bytes(),&m)
	if m["firstName"] != "test user" {
		t.Errorf("Expected first name to be 'test user' but got '%v'", m["firstName"])
	}

	if m["lastName"] != "lastname" {
		t.Errorf("Expected last name to be 'last name' but got, '%v'", m["lastName"])
	}

	if m["phoneNumber"] != 9989981212.0 {
		t.Errorf("Expected phone number to be 9989981212 but got, '%v'", m["phonenumber"])
	}

	if m["email"] != "bob@cool.com" {
		t.Errorf("Expected email to be 75 but got, '%v'", m["email"])
	}

	if m["previousFlight"] != "AC1212" {
		t.Errorf("Expected previous flight to be 75 but got, '%v'", m["previousflight"])
	}

	if m["nextFlight"] != "BC87" {
		t.Errorf("Expected next flight to be 75 but got, '%v'", m["nextflight"])
	}

	// the id is compared to 1.0 because JSON unmarshaling converts numbers to
    // floats, when the target is a map[string]interface{}
    if m["id"] != 1.0 {
        t.Errorf("Expected user ID to be '1'. Got '%v'", m["id"])
    }
}

func TestGetUser (t *testing.T){
	clearTable()
	addUsers(1)
	req, _ := http.NewRequest("GET","/user/1",nil)
	response := executeRequest (req)
	var results map[string]interface{}
	json.Unmarshal(response.Body.Bytes(), &results)
	t.Log(results["id"])
	checkResponseCode (t, http.StatusOK, response.Code)
} 

func addUsers(count int){
	if count <1 {
		count = 1
	}

	for i := 0 ; i < count; i++{
		statement := fmt.Sprintf("INSERT INTO users(firstName, lastName, phoneNumber, email, nextFlight, previousFlight) VALUES('%s','%s', %d,'%s','%s','%s')", "firstname","lastname",1112223333+i,"email@email.com","ac898","ed989")
		a.DB.Exec(statement)
	}
	
}

func TestUpdateUser (t *testing.T){
	clearTable()
	addUsers(1)
	req, _ := http.NewRequest("GET","/user/1",nil)
	response := executeRequest (req)
	var originalUser map[string]interface{}
	json.Unmarshal(response.Body.Bytes(), &originalUser)

	payload := []byte(`{"firstname":"test user","lastname":"new lastname","phonenumber":9989981212,"email":"bob@cool.com","previousflight":"AC1212","nextflight":"BC87"}`)
	req, _ = http.NewRequest("PUT", "/user/1", bytes.NewBuffer(payload))
	response = executeRequest (req)
	checkResponseCode (t, http.StatusOK, response.Code)

	var m map[string]interface{}
	json.Unmarshal(response.Body.Bytes(), &m)

	if m["id"] != originalUser["id"]{
		t.Errorf("Expected id to remain the same but changed id '%v' and original id was '%v'", m["id"], originalUser["id"])
	}
	if m["firstName"] == originalUser["firstName"]{
		t.Errorf("Expected first name to change but new name is '%v' and original name was '%v'", m["firstName"], originalUser["firstName"])
	}
	if m["lastName"] == originalUser["lastName"]{
		t.Errorf("Expected last name to change but new last name is '%v' and original lastname was '%v'", m["lastName"], originalUser["lastName"])
	}
	if m["phoneNumber"] == originalUser["phoneNumber"]{
		t.Errorf("Expected number to change but new number is '%v' and original number was '%v'", m["phoneNumber"], originalUser["phoneNumber"])
	}
	if m["email"] == originalUser["email"]{
		t.Errorf("Expected email to change but new email is '%v' and original email was '%v'", m["email"], originalUser["email"])
	}
	if m["nextFlight"] == originalUser["nextFlight"]{
		t.Errorf("Expected nextflight to change but new nextflight is '%v' and original nextflight was '%v'", m["nextFlight"], originalUser["nextFlight"])
	}
	if m["previousFlight"] == originalUser["previousFlight"]{
		t.Errorf("Expected previousflight to change but new previousflight is '%v' and original previousflightwas '%v'", m["previousFlight"], originalUser["previousFlight"])
	}
}

func TestDeleteuser (t *testing.T){
	clearTable()
	addUsers(1)

	req, _ := http.NewRequest("GET", "/user/1", nil)
	response := executeRequest (req)
	checkResponseCode (t, http.StatusOK, response.Code)

	//t.Log("delete")
	req, _ = http.NewRequest("DELETE", "/user/1", nil)
	response = executeRequest (req)
	t.Log(response.Body)
	checkResponseCode (t, http.StatusOK, response.Code)

	//t.Log("get")
	req, _ = http.NewRequest("GET", "/user/1", nil)
	response = executeRequest (req)
	checkResponseCode (t, http.StatusNotFound, response.Code)

}
