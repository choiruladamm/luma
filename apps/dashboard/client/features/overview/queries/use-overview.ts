import { useQuery } from "@tanstack/react-query";
import { getOverview } from "../api/overview-api";
import { overviewKeys } from "./query-keys";

export const useOverview = () => useQuery({ queryKey: overviewKeys.all, queryFn: getOverview });
