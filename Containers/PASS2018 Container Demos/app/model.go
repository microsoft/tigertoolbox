// model.go
package main
import (
	"fmt"
    "database/sql"

)
type user struct {
    ID    int    `json:"id"`
    FirstName  string `json:"firstName"`
	LastName   string    `json:"lastName"`
	MemberID   string    `json:"memberID"`
	PhoneNumber int   `json:"phoneNumber"`
	Email   string    `json:"email"`
	NextFlight  string   `json:"nextFlight"`
	PreviousFlight   string   `json:"previousFlight"`
}
func (u *user) getUser(db *sql.DB) error {
	statement := fmt.Sprintf("SELECT firstName, lastName, convert(nvarchar(50), memberID) as memberID, phoneNumber, email, nextFlight, previousFlight FROM users WHERE id=%d", u.ID)
	return db.QueryRow(statement).Scan(&u.FirstName, &u.LastName, &u.MemberID, &u.PhoneNumber, &u.Email, &u.NextFlight, &u.PreviousFlight)
}
func (u *user) updateUser(db *sql.DB) error {
	statement := fmt.Sprintf("UPDATE users SET firstName='%s',lastName='%s', phoneNumber=%d, email='%s', nextFlight='%s', previousFlight='%s' WHERE id=%d", u.FirstName, u.LastName, u.PhoneNumber, u.Email, u.NextFlight, u.PreviousFlight, u.ID)
	_, err := db.Exec(statement)
	return err
}
func (u *user) deleteUser(db *sql.DB) error {
	statement := fmt.Sprintf("DELETE FROM users WHERE id=%d", u.ID)
	_, err := db.Exec(statement)
	return err
}
func (u *user) createUser(db *sql.DB) error {
    statement := fmt.Sprintf("INSERT INTO users(firstName, lastName, phoneNumber, email, nextFlight, previousFlight) VALUES ('%s','%s',%d,'%s','%s','%s')", u.FirstName, u.LastName, u.PhoneNumber, u.Email, u.NextFlight, u.PreviousFlight)
	//fmt.Println(statement)
	_, err := db.Exec(statement)
	if err != nil {
		return err
	}
	
	err = db.QueryRow("SELECT TOP 1 ID from users order by ID DESC").Scan(&u.ID)
	if err != nil{
		return err
	}
	return nil	
}

func getUsers(db *sql.DB, start, count int) ([]user, error) {
	statement := fmt.Sprintf("SELECT top %d id, firstName, lastName, convert(nvarchar(50), memberID) as memberID, phoneNumber, email, nextFlight, previousFlight from users where id > %d", count, start)
	rows, err:= db.Query(statement)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	users := []user{}

	for rows.Next(){
		var u user
		if err := rows.Scan(&u.ID, &u.FirstName, &u.LastName, &u.MemberID, &u.PhoneNumber, &u.Email, &u.NextFlight, &u.PreviousFlight); err != nil {
			return nil, err
		}
		users = append(users, u)
	}

	return users, nil
}