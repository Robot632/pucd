# Colonia P.U.C.D.

Site separat pentru colonie, făcut după site-ul de vot `Robot632/vot`:
login cu cod, votări (obișnuite, legi, recrutare), panou de comandant,
membri cu funcții și lista „Armata coloniei” vizibilă pentru toți.

## Cum îl pui online (o singură dată)

1. **Baza de date** – intră pe supabase.com → *New project* (unul NOU, nu cel al partidului).
2. În proiect: *SQL Editor* → *New query* → lipește tot `setup.sql` → *Run*.
   Jos apar două coduri: **ADMIN** (comandantul) și **TEST** (cont de probă).
   Păstrează-le; dacă le pierzi, rulează din nou ultimul `select` din fișier.
3. *Project Settings → API*: copiază **Project URL** și cheia **anon public**
   și pune-le în `index.html` la `SUPABASE_URL` și `SUPABASE_KEY`.
4. **GitHub** – creează un repo nou (ex. `pucd`), urcă `index.html`,
   apoi *Settings → Pages → Branch: main → Save*.
   Site-ul va fi la `https://robot632.github.io/pucd/`.

## Folosire

- Comandantul intră cu codul ADMIN și adaugă membrii în secțiunea **Membri**
  (fiecare primește un cod pe care i-l trimiți).
- Butonul **Funcție** de lângă fiecare membru îi schimbă funcția
  (General, Colonel, Soldat… sau scrii una nouă).
- Pentru a da și altcuiva drept de comandant, în Supabase → *Table editor* →
  `members` → bifează `is_admin` la acel membru.
