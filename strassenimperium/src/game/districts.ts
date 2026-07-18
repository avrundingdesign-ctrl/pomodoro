import type { Db, DistrictRow, UserRow } from "../db.js";

export function listDistricts(db: Db): DistrictRow[] {
  return db
    .prepare("SELECT * FROM districts ORDER BY move_cost ASC, id ASC")
    .all() as unknown as DistrictRow[];
}

export function getDistrict(db: Db, id: number): DistrictRow | undefined {
  return db.prepare("SELECT * FROM districts WHERE id = ?").get(id) as unknown as
    | DistrictRow
    | undefined;
}

/** Stadtteil des Spielers; Fallback auf das Startviertel. */
export function districtOf(db: Db, user: Pick<UserRow, "district_id">): DistrictRow {
  return (
    getDistrict(db, user.district_id) ??
    (db
      .prepare("SELECT * FROM districts ORDER BY id ASC LIMIT 1")
      .get() as unknown as DistrictRow)
  );
}
