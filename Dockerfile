FROM feliperaposo/protheus-docker-baselight:24
LABEL maintainer="Felipe Raposo <feliperaposo@gmail.com>"
EXPOSE 1234/tcp
COPY ./root/ /
CMD ["/compile.sh"]
