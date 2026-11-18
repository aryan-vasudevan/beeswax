-- Reflections are recollections written looking back (BWX-60). A new enum
-- value cannot be used in the transaction that adds it, so it gets its own
-- migration; 20261024090100_prompts_and_sealing.sql uses it.

alter type public.recollection_kind add value 'reflection';
