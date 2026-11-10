-- The language choice of BeautifulRogue. BeautifulRogue reads its texts while its files load, which is earlier than
-- its own saved variables exist. This addon loads first (BeautifulRogue lists it as an optional dependency), so its
-- saved variable is there in time. The table below is replaced by the saved one right after this file ran.
BeautifulRogueLanguageDB = BeautifulRogueLanguageDB or {}   -- lint:ignore (only the default; the saved table replaces it)
