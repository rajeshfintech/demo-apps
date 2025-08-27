bind = "0.0.0.0:8080"
worker_class = "gthread"
workers = 2          # tune up on bigger CPUs
threads = 4
timeout = 60         # time for a *busy* request
graceful_timeout = 30
keepalive = 2        # don’t sit long on idle sockets
accesslog = "-"
errorlog = "-"

