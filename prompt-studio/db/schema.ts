import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const usageBuckets = sqliteTable("usage_buckets", {
  bucketKey: text("bucket_key").primaryKey(),
  count: integer("count").notNull().default(0),
  expiresAt: integer("expires_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
});
