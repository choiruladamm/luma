import { Skeleton } from "../../../components/ui/skeleton";

/** Board 12 stat value + note blocks, for StatCard while the overview loads. */
export const StatValueSkeleton = () => <Skeleton className="h-9 w-24 rounded-[10px]" />;
export const StatNoteSkeleton = () => <Skeleton className="h-3 w-[120px]" />;
