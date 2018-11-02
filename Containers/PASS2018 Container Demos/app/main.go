// main.go

package main

func main() {
    a := App{} 
    // You need to set your Username and Password here
    a.Initialize("AppLogin", "yourStrongPassw0rd!", "db", "rest_api_example")

    a.Run(":8080")
}