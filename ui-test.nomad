job "ui-test" {
  datacenters = ["dev"]

  group "ui" {
    network {
      mode = "host"

      port "http" {
        static = 8085
      }
    }

    task "ui" {
      driver = "docker"

      config {
        image = "cule-ui:dev"
        ports = ["http"]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
