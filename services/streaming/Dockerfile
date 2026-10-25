FROM flink:1.20-scala_2.12

USER root

# Install python, pip, wget and JDK for PyFlink native extensions
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    wget \
    openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# Create symlink for python
RUN ln -s /usr/bin/python3 /usr/bin/python

# Fix PyFlink / pemja JDK path issue
# We create the expected directory and link it to the actual JDK include folder
RUN mkdir -p /opt/java/openjdk && \
    (ln -s /usr/lib/jvm/java-17-openjdk-arm64/include /opt/java/openjdk/include || \
     ln -s /usr/lib/jvm/java-17-openjdk-amd64/include /opt/java/openjdk/include)

# Install PyFlink
RUN pip3 install apache-flink==1.20.0

RUN mkdir -p /opt/flink/lib

USER flink
