job "hello" {
  datacenters = ["dev"]
  type = "service"

  group "hello" {
    count = 1

    task "hello" {
      driver = "docker"

      config {
        image   = "alpine:3.19"
        command = "sh"
        args    = ["-c", "echo 'Hello from Nomad'; sleep 60"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
