-- Vitesses supplémentaires des créatures (Bruno, 2026-10-05) : Escalade, Nage et Vol (en cases, 0 = aucune),
-- et pour le Vol une précision : lévitation, stationnaire ou parfait (facultative, seulement si le vol > 0).
alter table creature
  add column vitesse_escalade integer not null default 0 check (vitesse_escalade between 0 and 99),
  add column vitesse_nage integer not null default 0 check (vitesse_nage between 0 and 99),
  add column vitesse_vol integer not null default 0 check (vitesse_vol between 0 and 99),
  add column vol_type text check (vol_type is null or vol_type in ('levitation', 'stationnaire', 'parfait'));
