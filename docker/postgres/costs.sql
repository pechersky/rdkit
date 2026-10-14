
-- Appended to upstream's 4.7.0 -> 4.8.0 update script after the Dockerfile deletes
-- its ALTER FUNCTION ... COST 100 lines.
--
-- Why COST 100: PostgreSQL defaults C functions to COST 1, so the planner treats
-- RDKit calls (mol_to_svg, fingerprints, substructure) as nearly free and may run
-- them on every row before a LIMIT or join filter. Upstream's 4.8.0 extension sets
-- COST 100 on all cartridge functions (rdkit/rdkit#8711, rdkit/rdkit#8784).
--
-- Why not upstream's lines: 29 of them fail (27 have DEFAULT clauses in the argument
-- list, one has a trailing -- comment that swallows its COST clause, one names
-- fmcs_smiles_transitionmol, which doesn't exist), so ALTER EXTENSION rdkit UPDATE
-- aborts. Still so on upstream master (rdkit/rdkit#9709). Instead, set the same
-- cost on every C function the extension actually owns.
--
-- Why patch a release at all: without this, no database created before RDKit
-- 2025_09_1 (extension 4.8.0), including anything from Aurora's 4.6.1, can be
-- updated in place. The -unpatched images (PATCH_COSTS empty) ship upstream's
-- script as released. Delete this file once upstream's script works.
DO $costs$
DECLARE f pg_catalog.regprocedure;
BEGIN
  FOR f IN
    SELECT p.oid FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_depend d ON d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass AND d.objid = p.oid
    JOIN pg_catalog.pg_extension e ON d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass AND d.refobjid = e.oid
    WHERE d.deptype = 'e' AND e.extname = 'rdkit' AND p.prokind = 'f'
      AND p.prolang = (SELECT oid FROM pg_catalog.pg_language WHERE lanname = 'c')
  LOOP
    EXECUTE pg_catalog.format('ALTER FUNCTION %s COST 100', f);
  END LOOP;
END
$costs$;
