Wenn ein Task abgeschlossen ist, am Ende genau einmal committen und pushen, mit einer passenden Commit-Message.

Danach den Installationsordner aus der lokalen `.env` lesen (`WOW_ADDON_DIR`). Das alte Addon dort löschen und die aktuelle Version hineinkopieren. `.git` nicht mitkopieren. Die `.env` nicht committen und nicht mitkopieren.

Wenn keine `.env` da ist oder `WOW_ADDON_DIR` leer ist, nicht kopieren und eine Warnung ausgeben.
