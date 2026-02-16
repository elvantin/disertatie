-- ============================================================
-- SC MEDIA SRL - Business Database Seed Data
-- Database: mediasrl_business
-- Purpose: CRM data (clients, services, projects, employees, invoices)
-- Data is coherent with WordPress site content and API responses
-- ============================================================

CREATE DATABASE IF NOT EXISTS mediasrl_business
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE mediasrl_business;

-- ============================================================
-- Table: angajati (employees)
-- ============================================================

CREATE TABLE IF NOT EXISTS angajati (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nume VARCHAR(100) NOT NULL,
  prenume VARCHAR(100) NOT NULL,
  functie VARCHAR(150) NOT NULL,
  departament VARCHAR(100) NOT NULL,
  email VARCHAR(200) NOT NULL,
  telefon VARCHAR(20),
  data_angajare DATE NOT NULL,
  salariu_brut DECIMAL(10,2),
  status ENUM('activ', 'inactiv', 'concediu') DEFAULT 'activ',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO angajati (nume, prenume, functie, departament, email, telefon, data_angajare, salariu_brut, status) VALUES
('Popescu', 'Elena', 'Director General si Fondator', 'Management', 'elena.popescu@media-srl.ro', '+40 721 100 001', '2018-03-15', 12000.00, 'activ'),
('Ionescu', 'Andrei', 'Director Creativ', 'Creatie', 'andrei.ionescu@media-srl.ro', '+40 721 100 002', '2019-06-01', 9500.00, 'activ'),
('Dumitrescu', 'Maria', 'Social Media Manager', 'Digital', 'maria.dumitrescu@media-srl.ro', '+40 721 100 003', '2020-09-15', 7500.00, 'activ'),
('Popa', 'Cristian', 'Specialist PR si Comunicare', 'PR', 'cristian.popa@media-srl.ro', '+40 721 100 004', '2021-02-01', 7000.00, 'activ'),
('Vasilescu', 'Ana', 'Account Manager', 'Client Service', 'ana.vasilescu@media-srl.ro', '+40 721 100 005', '2022-01-10', 7500.00, 'activ');

-- ============================================================
-- Table: servicii (services)
-- ============================================================

CREATE TABLE IF NOT EXISTS servicii (
  id INT AUTO_INCREMENT PRIMARY KEY,
  denumire VARCHAR(200) NOT NULL,
  descriere TEXT,
  pret_lunar DECIMAL(10,2) COMMENT 'Pret minim lunar in RON (NULL = per proiect)',
  pret_proiect DECIMAL(10,2) COMMENT 'Pret minim per proiect in RON (NULL = lunar)',
  categorie VARCHAR(100) NOT NULL,
  status ENUM('activ', 'inactiv') DEFAULT 'activ',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO servicii (denumire, descriere, pret_lunar, pret_proiect, categorie, status) VALUES
('PR si Comunicare Strategica', 'Strategie de comunicare, comunicate de presa, relatii cu media, monitorizare media, gestionare crize', 2500.00, NULL, 'PR', 'activ'),
('Social Media Management', 'Strategie continut, creare postari, community management, campanii platite, rapoarte lunare', 2000.00, NULL, 'Digital', 'activ'),
('Branding si Identitate Vizuala', 'Design logo, manual de brand, materiale de prezentare, branding digital, rebranding complet', NULL, 5000.00, 'Creatie', 'activ'),
('Organizare Evenimente', 'Conferinte de presa, lansari produse, evenimente corporate, webinarii, logistica completa', NULL, 3000.00, 'Evenimente', 'activ'),
('Marketing Digital', 'Google Ads, SEO, email marketing, content marketing, analiza si optimizare continua', 3500.00, NULL, 'Digital', 'activ'),
('Consultanta Strategica', 'Audit comunicare, plan strategic, training echipe interne, mentoring departamente marketing', NULL, 1500.00, 'Consultanta', 'activ');

-- ============================================================
-- Table: clienti (clients)
-- ============================================================

CREATE TABLE IF NOT EXISTS clienti (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nume_companie VARCHAR(200) NOT NULL,
  cui VARCHAR(20),
  persoana_contact VARCHAR(200),
  functie_contact VARCHAR(150),
  email VARCHAR(200) NOT NULL,
  telefon VARCHAR(20),
  adresa VARCHAR(300),
  industrie VARCHAR(100),
  data_inregistrare DATE NOT NULL,
  status ENUM('activ', 'inactiv', 'prospect') DEFAULT 'activ',
  nota TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO clienti (nume_companie, cui, persoana_contact, functie_contact, email, telefon, adresa, industrie, data_inregistrare, status, nota) VALUES
('TechVision SRL', 'RO 39876543', 'Mihai Stanescu', 'CEO', 'mihai.stanescu@techvision.ro', '+40 742 200 001', 'Str. Fabricii 12, Cluj-Napoca', 'Tehnologie', '2024-11-15', 'activ', 'Client strategic - contract rebranding complet finalizat cu succes'),
('GreenLeaf Bio SRL', 'RO 40123456', 'Ioana Marinescu', 'Director Marketing', 'ioana@greenleafbio.ro', '+40 742 200 002', 'Str. Plantelor 8, Brasov', 'Cosmetice', '2025-02-01', 'activ', 'Client fidel - campanie social media cu rezultate excelente'),
('Cafe Central SRL', 'RO 38765432', 'Alexandru Radulescu', 'Proprietar', 'alex@cafecentral.ro', '+40 742 200 003', 'Bd. Magheru 30, Bucuresti', 'HoReCa', '2025-04-10', 'activ', 'Lant de cafenele artizanale - 3 locatii in Bucuresti'),
('HealthPlus SRL', 'RO 41567890', 'Dr. Carmen Moldovan', 'Director Medical', 'carmen.moldovan@healthplus.ro', '+40 742 200 004', 'Str. Aviatorilor 15, Bucuresti', 'Sanatate', '2025-08-20', 'activ', 'Clinica medicala privata - contract pe 12 luni'),
('AutoSpeed SRL', 'RO 37654321', 'Bogdan Gheorghe', 'Director General', 'bogdan@autospeed.ro', '+40 742 200 005', 'Calea Dorobantilor 90, Bucuresti', 'Auto', '2025-06-01', 'activ', 'Dealer auto premium - campanii Google Ads'),
('EduSmart Academy SRL', 'RO 42345678', 'Prof. Laura Tanase', 'Director', 'laura@edusmart.ro', '+40 742 200 006', 'Str. Academiei 5, Iasi', 'Educatie', '2025-10-15', 'activ', 'Cursuri online si offline - necesita strategie completa'),
('AgroFresh SRL', 'RO 36543210', 'Ion Munteanu', 'Administrator', 'ion@agrofresh.ro', '+40 742 200 007', 'Sat Baneasa, Jud. Giurgiu', 'Agricultura', '2025-05-20', 'inactiv', 'Producator legume bio - contract incheiat dupa campania de sezon'),
('FinConsult Partners SRL', 'RO 43210987', 'Adriana Nistor', 'Managing Partner', 'adriana@finconsult.ro', '+40 742 200 008', 'Str. Doamnei 22, Bucuresti', 'Financiar', '2026-01-10', 'prospect', 'In discutii pentru contract de PR financiar');

-- ============================================================
-- Table: proiecte (projects)
-- ============================================================

CREATE TABLE IF NOT EXISTS proiecte (
  id INT AUTO_INCREMENT PRIMARY KEY,
  client_id INT NOT NULL,
  serviciu_id INT NOT NULL,
  denumire VARCHAR(300) NOT NULL,
  descriere TEXT,
  data_start DATE NOT NULL,
  data_finalizare DATE,
  status ENUM('planificat', 'in_derulare', 'finalizat', 'anulat') DEFAULT 'planificat',
  buget DECIMAL(12,2),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (client_id) REFERENCES clienti(id),
  FOREIGN KEY (serviciu_id) REFERENCES servicii(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO proiecte (client_id, serviciu_id, denumire, descriere, data_start, data_finalizare, status, buget) VALUES
(1, 3, 'Rebranding complet TechVision', 'Identitate vizuala noua, website, materiale de prezentare, campanie de lansare', '2025-01-15', '2025-06-30', 'finalizat', 25000.00),
(1, 1, 'PR pentru lansare brand nou TechVision', 'Comunicate de presa, media outreach, articole sponsorizate', '2025-04-01', '2025-06-30', 'finalizat', 8000.00),
(2, 2, 'Social Media GreenLeaf Bio', 'Gestionare Instagram + Facebook, campanii platite, continut educativ', '2025-03-01', '2025-08-31', 'finalizat', 12000.00),
(3, 4, 'Lansare linie cafea specialty Cafe Central', 'Eveniment lansare, colaborari influenceri, campanie Instagram', '2025-05-01', '2025-07-15', 'finalizat', 8000.00),
(4, 1, 'Strategie comunicare HealthPlus', 'PR medical, articole specialitate, gestionare recenzii, Google Ads', '2025-09-01', NULL, 'in_derulare', 18000.00),
(4, 5, 'Marketing Digital HealthPlus', 'Campanii Google Ads, SEO medical, email marketing pacienti', '2025-09-15', NULL, 'in_derulare', 21000.00),
(5, 5, 'Google Ads AutoSpeed', 'Campanii Search si Display pentru modele premium', '2025-06-15', NULL, 'in_derulare', 15000.00),
(6, 6, 'Consultanta strategie EduSmart', 'Audit comunicare, plan strategic 12 luni, training echipa interna', '2025-11-01', '2025-12-15', 'finalizat', 4500.00),
(6, 2, 'Social Media EduSmart Academy', 'Gestionare LinkedIn + Facebook, continut educational, campanii admitere', '2026-01-15', NULL, 'in_derulare', 10000.00),
(7, 2, 'Campanie sezon AgroFresh', 'Social media + PR pentru sezonul de legume bio', '2025-05-20', '2025-09-30', 'finalizat', 6000.00);

-- ============================================================
-- Table: facturi (invoices)
-- ============================================================

CREATE TABLE IF NOT EXISTS facturi (
  id INT AUTO_INCREMENT PRIMARY KEY,
  client_id INT NOT NULL,
  proiect_id INT NOT NULL,
  numar_factura VARCHAR(50) NOT NULL UNIQUE,
  suma DECIMAL(12,2) NOT NULL,
  tva DECIMAL(12,2) NOT NULL,
  total DECIMAL(12,2) NOT NULL,
  data_emitere DATE NOT NULL,
  data_scadenta DATE NOT NULL,
  status ENUM('emisa', 'platita', 'scadenta', 'anulata') DEFAULT 'emisa',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (client_id) REFERENCES clienti(id),
  FOREIGN KEY (proiect_id) REFERENCES proiecte(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO facturi (client_id, proiect_id, numar_factura, suma, tva, total, data_emitere, data_scadenta, status) VALUES
(1, 1, 'MED-2025-001', 12500.00, 2375.00, 14875.00, '2025-03-01', '2025-03-31', 'platita'),
(1, 1, 'MED-2025-002', 12500.00, 2375.00, 14875.00, '2025-06-30', '2025-07-30', 'platita'),
(1, 2, 'MED-2025-003', 8000.00, 1520.00, 9520.00, '2025-06-30', '2025-07-30', 'platita'),
(2, 3, 'MED-2025-004', 6000.00, 1140.00, 7140.00, '2025-05-01', '2025-05-31', 'platita'),
(2, 3, 'MED-2025-005', 6000.00, 1140.00, 7140.00, '2025-08-31', '2025-09-30', 'platita'),
(3, 4, 'MED-2025-006', 8000.00, 1520.00, 9520.00, '2025-07-15', '2025-08-15', 'platita'),
(4, 5, 'MED-2025-007', 4500.00, 855.00, 5355.00, '2025-10-01', '2025-10-31', 'platita'),
(4, 5, 'MED-2025-008', 4500.00, 855.00, 5355.00, '2025-12-01', '2025-12-31', 'platita'),
(4, 6, 'MED-2025-009', 7000.00, 1330.00, 8330.00, '2025-11-01', '2025-12-01', 'platita'),
(5, 7, 'MED-2025-010', 5000.00, 950.00, 5950.00, '2025-09-01', '2025-09-30', 'platita'),
(5, 7, 'MED-2026-011', 5000.00, 950.00, 5950.00, '2026-01-15', '2026-02-15', 'emisa'),
(6, 8, 'MED-2025-012', 4500.00, 855.00, 5355.00, '2025-12-15', '2026-01-15', 'platita'),
(6, 9, 'MED-2026-013', 5000.00, 950.00, 5950.00, '2026-02-01', '2026-03-01', 'emisa'),
(7, 10, 'MED-2025-014', 6000.00, 1140.00, 7140.00, '2025-09-30', '2025-10-30', 'platita');

-- ============================================================
-- View: sumar financiar per client
-- ============================================================

CREATE OR REPLACE VIEW v_sumar_clienti AS
SELECT
  c.id AS client_id,
  c.nume_companie,
  c.industrie,
  c.status AS status_client,
  COUNT(DISTINCT p.id) AS nr_proiecte,
  SUM(CASE WHEN p.status = 'finalizat' THEN 1 ELSE 0 END) AS proiecte_finalizate,
  SUM(CASE WHEN p.status = 'in_derulare' THEN 1 ELSE 0 END) AS proiecte_active,
  COALESCE(SUM(f.total), 0) AS total_facturat,
  COALESCE(SUM(CASE WHEN f.status = 'platita' THEN f.total ELSE 0 END), 0) AS total_incasat
FROM clienti c
LEFT JOIN proiecte p ON p.client_id = c.id
LEFT JOIN facturi f ON f.client_id = c.id
GROUP BY c.id, c.nume_companie, c.industrie, c.status;

-- ============================================================
-- View: statistici companie
-- ============================================================

CREATE OR REPLACE VIEW v_statistici AS
SELECT
  (SELECT COUNT(*) FROM clienti WHERE status = 'activ') AS clienti_activi,
  (SELECT COUNT(*) FROM clienti) AS total_clienti,
  (SELECT COUNT(*) FROM proiecte WHERE status = 'finalizat') AS proiecte_finalizate,
  (SELECT COUNT(*) FROM proiecte WHERE status = 'in_derulare') AS proiecte_active,
  (SELECT COUNT(*) FROM proiecte) AS total_proiecte,
  (SELECT COUNT(*) FROM angajati WHERE status = 'activ') AS angajati_activi,
  (SELECT COALESCE(SUM(total), 0) FROM facturi WHERE status = 'platita') AS venit_total_incasat,
  (SELECT COALESCE(SUM(total), 0) FROM facturi WHERE status = 'emisa') AS facturi_neincasate,
  (SELECT COUNT(*) FROM servicii WHERE status = 'activ') AS servicii_active;
