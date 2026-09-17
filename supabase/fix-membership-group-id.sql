-- VICOBA OS fix: public join requests identify the group by invite_code only
-- (they can't reference a groups.id row), so group_id must be optional here.
alter table membership_applications alter column group_id drop not null;
