FROM telegraf:1.29
RUN apt-get update -qq &&     apt-get install -y --no-install-recommends smartmontools &&     apt-get clean && rm -rf /var/lib/apt/lists/*
