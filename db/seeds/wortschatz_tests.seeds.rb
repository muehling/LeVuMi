# -*- encoding : utf-8 -*-
items = %w{
ab
aber
am
an
auch
auf
aus
Auto
Baum
bei
beim
bin
bis
da
danach
das
dein
deine
deiner
dem
den
der
des
dich
dir
doch
du
eine
einer
ein
einen
einem
eines
er
es
geben
gegen
gehen
gerade
gut
haben
hat
habe
Haus
her
hin
hoch
ich
im
in
kaufen
kein
keine
keiner
laufen
machen
mal
Mama
man
mein
meine
mich
mir
mit
nach
nein
noch
Note
nun
nur
ob
oder
Oma
Opa
Papa
raus
rufen
sagen
schon
Schule
sehen
sei
seid
sein
seine
seiner
seit
sich
sogar
so
Tag
Tage
tun
um
warum
war
was
weg
weil
weit
weiter
wem
wen
wenig
weniger
wer
wir
wo
Woche
}

cbmN2 = TestCBM.create(name: "Sichtwortschatz", len: items.size, info: "", short_info: "", time: 60, subject: "Deutsch", construct: "Wortschatz", level: "Niveaustufe 2", archive: false)

items.each do |i|
  it = cbmN2.items.build(itemtext: i, difficulty: 0, itemtype: 0)
  it.save
end

cbmN2.save



items = %w{
Abend
alle
alles
als
also
alt
älter
andere
anders
aufwachen
bald
Bäume
bekommen
besser
Bett
bist
bitten
bleiben
bleibt
Brief
bringen
bringt
Bruder
Bürder
dann
darf
dass
denken
die
dies
diese
dieser
dort
drei
durch
dürfen
einmal
eins
einzelnen
Eltern
erst
erstens
erzählen
essen
isst
etwas
euch
euer
eure
fahren
fährt
fallen
fällt
Familie
fangen
fängt
fast
Ferien
finden
fliegen
fliegt
fragen
fragt
Frau
freuen
Freude
Freund
Freundin
für
ganz
ganze
ganzer
gibt
Geburt
Geburtstag
gefallen
gefällt
geht
gern
gestern
gewinnen
gleich
groß
größer
grüßen
Gruß
hallo
Häuser
hatte
heißen
heute
hier
hinter
hoffen
hoffentlich
höher
hören
Hund
Hunde
ihm
ihn
ihnen
ihr
ihre
immer
ins
ist
ja
Jahr
Jahre
jede
jeder
jedes
jetzt
Katze
Kind
Kinder
Klasse
klein
kommen
können
kann
kriegen
lang
länger
läuft
lernen
letzte
letzter
lieb
lieben
liegen
Mann
Männer
Meer
mehr
möchten
mögen
morgen
müssen
muss
Mütter
Mutter
nächste
Nächte
nachts
nehmen
nimmt
neu
nicht
nichts
nie
oft
ohne
paar
plötzlich
rennen
rannte
sagt
schlafen
schläft
schnell
schöne
schreiben
schreibt
Schwester
schwimmen
schwamm
geschwommen
sieht
sehr
selbst
sieht
sind
sitzen
sitzt
sollen
Spaß
Späße
spät
verspäten
Spiel
spielen
springen
stehen
steht
Stunde
Tier
toll
über
Uhr
und
uns
unsere
unser
unter
viel
vielleicht
vier
vor
wachen
Wald
Wälder
wann
Wasser
weit
welche
welcher
Welt
wenn
werden
wird
wie
wieder
wissen
weiß
wusste
wohnen
wollen
will
wünschen
Zeit
zu
zum
zur
zurück
zusammen
zwei
}


cbmN4 = TestCBM.create(name: "Sichtwortschatz", len: items.size, info: "", short_info: "", time: 60, subject: "Deutsch", construct: "Wortschatz", level: "Niveaustufe 4", archive: false)

items.each do |i|
  it = cbmN4.items.build(itemtext: i, difficulty: 0, itemtype: 0)
  it.save
end

cbmN4.save
