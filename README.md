# PowerShell Praxisarbeit

Diese arbeit wurde im rahmen des Moduls 122 erarbeitet und soll meine Fähigkeit und mein Verständnis belegen.
Thema der Praxisarbeit `Dateilverwaltung für Webprojekte`

## Situation

Firma xy hat ein Shared drive welches innerhalb der Firma über Jahre hinweg von verschiendenen Entwicklern benutzt wurde. Um das Drive aufzuräumen wurde dieses Powershell Skript geschrieben, es soll alle Projekte aus den Verschiedenen ebenen extrahieren, gleiche versionieren & Schlussendlich alle auf eine ebene Verschieben.<br>
Um die Kriterien der Arbeit zu erfüllen werden alle Projekte die Verschoben werden in einem Log festgehalten. Optional kann auch nur ein Log der gefundenen Projekte erstellt werden, ohne diese tatsächlich zu verschieben.

## Umgebung

Herunterladen und in Visual Studio Code öffnen
```PowerShell
git clone https://github.com/fokklz/powershell-praxisarbeit
cd powershell-praxisarbeit
code .
```

**Ausführen:**<br>
Mit `>Run Task` kann `Praxisarbeit` ausgeführt werden um das Skript direkt Auszuführen.

**Entwicklung:**<br>
Mit `F5` kann der Debug Modus gestartet werden, dieser startet das Script und erlaubt es mit gewohnten Debugging Tools zu arbeiten

## Tasks:

| **Name**     | **Beschreibung**                                                          |
| ------------ | ------------------------------------------------------------------------- |
| Praxisarbeit | Führt das Script im "Produktionsmodus" aus                                |
| Setup Test   | Erstellt/Zurücksetzen der Testdaten                                       |
| Cleanup Test | Löschen der Testdaten (können mit `Setup Test` erneut hergestellt werden) |

## Testumgebung

Für das Skript habe ich einen Ordner kunstruiert welcher als "unordentliches" Shared-Drive angesehen werden kann, dieser ist in `test-drive.zip` enthalten. 



