-- Buzz for a cell hatching (BWX-122). A new enum value cannot be used in
-- the transaction that adds it, so it gets its own migration.

alter type public.buzz_kind add value 'hatched';
