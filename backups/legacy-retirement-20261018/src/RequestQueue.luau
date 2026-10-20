-- Fixed-sized FIFO batches. A wall-clock-dependent cut would change which
-- simulation step receives an accepted order, so batching is count-based.
local Queue={BatchSize=16,Capacity=256}
function Queue.Take(queue)
 local count=math.min(#queue,Queue.BatchSize);local batch=table.create(count)
 for i=1,count do batch[i]=queue[i]end
 local remaining=table.create(#queue-count)
 for i=count+1,#queue do remaining[i-count]=queue[i]end
 return batch,remaining
end
return Queue
