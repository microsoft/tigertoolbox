FROM boxfuse/flyway

COPY . /flyway/

RUN chmod +x /flyway/bin/wait-for-it.sh

ENTRYPOINT ["flyway"]  