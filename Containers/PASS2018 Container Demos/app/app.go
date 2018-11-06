// app.go

package main

import (
	"encoding/json"
	"strconv"
	"net/http"
    "database/sql"
    "github.com/gorilla/mux"
	_ "github.com/denisenkom/go-mssqldb"
	"github.com/gorilla/handlers"
	"fmt"
	"log"
)

type App struct {
    Router *mux.Router
    DB     *sql.DB
}

func (a *App) Initialize(user, password, host string, dbname string) {
    connectionString := fmt.Sprintf("user id=%s;password = %s;server=%s;database=%s", user, password, host ,dbname)
	var err error
    a.DB, err = sql.Open("sqlserver", connectionString)
    if err != nil {
        log.Fatal(err)
    }
	a.Router = mux.NewRouter()
	a.initializeRoutes()
}
func (a *App) initializeRoutes() {
    a.Router.HandleFunc("/users", a.getUsers).Methods("GET")
    a.Router.HandleFunc("/user", a.createUser).Methods("POST")
    a.Router.HandleFunc("/user/{id:[0-9]+}", a.getUser).Methods("GET")
    a.Router.HandleFunc("/user/{id:[0-9]+}", a.updateUser).Methods("PUT")
    a.Router.HandleFunc("/user/{id:[0-9]+}", a.deleteUser).Methods("DELETE")
}

func (a *App) Run(addr string) { 
	log.Fatal(http.ListenAndServe(addr, handlers.CORS(handlers.AllowedHeaders([]string{"X-Requested-With", "Content-Type", "Authorization"}), handlers.AllowedMethods([]string{"GET", "POST", "PUT", "HEAD", "OPTIONS"}), handlers.AllowedOrigins([]string{"*"}))(a.Router)))
}

func (a *App) getUser(w http.ResponseWriter, r *http.Request){
	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil{
		respondWithError(w, http.StatusBadRequest, "Invalid User ID")
		return
	}

	u := user{ID: id}
	if err := u.getUser(a.DB); err != nil{
		switch err{
		case sql.ErrNoRows:
			respondWithError(w, http.StatusNotFound, "user not found")
		default:
			respondWithError(w, http.StatusInternalServerError, err.Error())
		}
		return
	}
	respondWithJSON(w, http.StatusOK, u)
}

func respondWithError(w http.ResponseWriter, code int, message string) {
    respondWithJSON(w, code, map[string]string{"error": message})
}

func respondWithJSON(w http.ResponseWriter, code int, payload interface{}) {
    response, _ := json.Marshal(payload)
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(code)
    w.Write(response)
}

func (a *App) getUsers (w http.ResponseWriter, r *http.Request ){
	count, _ := strconv.Atoi(r.FormValue("count"))
	start, _ := strconv.Atoi(r.FormValue("start"))
	
	if count >10 || count <1 {
		count = 10 
	}
	if start < 0{
		start = 0
	}

	users, err := getUsers(a.DB, start, count)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}
	respondWithJSON(w, http.StatusOK, users)
}

func (a *App) createUser(w http.ResponseWriter, r *http.Request){
	var u user 
	decoder := json.NewDecoder(r.Body)
	if err := decoder.Decode(&u); err !=nil {
		respondWithError(w, http.StatusBadRequest, "invalid payload")
		return
	}
	defer r.Body.Close()

	if err := u.createUser(a.DB); err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}
	respondWithJSON(w, http.StatusCreated, u)
}

func (a *App) updateUser( w http.ResponseWriter, r *http.Request){
	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "user ID not found")
		return
	}

	var u user
	decoder := json.NewDecoder(r.Body)
	if err := decoder.Decode(&u); err != nil{
		respondWithError(w, http.StatusBadRequest, "invalid payload")
		return
	}

	defer r.Body.Close()
	u.ID = id

	if err := u.updateUser(a.DB); err !=nil{
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}
	respondWithJSON(w, http.StatusOK, u)
}


func (a *App) deleteUser( w http.ResponseWriter, r *http.Request){
	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "user ID not found")
		return
	}

	u := user{ID: id}

	if err := u.deleteUser(a.DB); err !=nil{
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}
	respondWithJSON(w, http.StatusOK, map[string]string{"result": "success"})
}