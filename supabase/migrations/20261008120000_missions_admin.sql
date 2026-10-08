-- Missions rédigées par Bruno dans l'administration (2026-10-08) : une mission peut exister avant que son
-- événement soit branché (valeur « a_brancher », sans effet). Bruno décrit en mots, dans declencheur_note, ce qui
-- doit la déclencher ; le branchement (déclencheur SQL) se fait ensuite à sa demande.
alter table mission drop constraint if exists mission_evenement_check;
alter table mission add constraint mission_evenement_check
  check (evenement in ('recrutement_paye', 'quete_reussie', 'a_brancher'));
alter table mission add column if not exists declencheur_note text not null default '';
