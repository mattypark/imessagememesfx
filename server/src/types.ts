export interface Env {
  DB: D1Database;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_P8?: string;
  APNS_TOPIC: string;
}

export interface User {
  id: string;
  name: string;
  created_at: number;
}

export interface Device {
  user_id: string;
  token: string;
  env: "sandbox" | "production";
  updated_at: number;
}

export interface Room {
  id: string;
  code: string;
  name: string;
  owner: string;
  created_at: number;
}
