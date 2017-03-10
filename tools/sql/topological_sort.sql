-- drop type if exists graph_edges cascade;

create type graph_edges as (
  node_from text,
  node_to text
);


-- DROP FUNCTION if exists topological_sort(_graph graph_edges[]);
-- Determines a topological ordering or reports that the graph is not a DAG.
CREATE OR REPLACE FUNCTION topological_sort(_graph graph_edges[])
returns table (
  node text,
  sort_order int
) as
$BODY$
declare
    _current_node text;
    _counter int not null default 0;
begin
    
    -- Create a temporary table for building the topological ordering
    CREATE temporary TABLE tmp_topological_sort_order
    (
        node text PRIMARY KEY,  -- The Node
        ordinal int NULL        -- Defines the topological ordering. NULL for nodes that are
    );                          -- not yet processed. Will be set as nodes are processed in topological order.
    
    -- Create a temporary copy of the edges in the graph that we can work on.
    CREATE temporary TABLE tmp_graph_edges
    (
        node_from text,  -- From Node
        node_to text,    -- To Node
        PRIMARY KEY (node_from, node_to)
    );
    -- expand all graph nodes from input array
    INSERT INTO tmp_graph_edges (node_from, node_to)
    SELECT g.node_from, g.node_to
    FROM unnest(_graph) g
    where g.node_from is not null
      and g.node_to is not null
      and g.node_from != g.node_to;

    -- Create a temporary copy of the edges in the graph that we can work on.
    CREATE temporary TABLE tmp_nodes
    (
        node  text not null,     -- node
        PRIMARY KEY (node)
    );
    -- get all unique nodes from edges
    INSERT INTO tmp_nodes (node)
    SELECT distinct g.node_from FROM unnest(_graph) g where g.node_from is not null
    union
    SELECT distinct g.node_to FROM unnest(_graph) g where g.node_to is not null;


    -- Create a temporary copy of the edges in the graph that we can work on.
    CREATE temporary TABLE tmp_temp_graph_edges
    (
        node_from text,  -- From Node
        node_to text,    -- To Node
        PRIMARY KEY (node_from, node_to)
    );

    -- Grab a copy of all the edges in the graph, as we will
    -- be deleting edges as the algorithm runs.
    INSERT INTO tmp_temp_graph_edges (node_from, node_to)
    SELECT e.node_from, e.node_to
    FROM tmp_graph_edges e;

    -- Start by inserting all the nodes that have no incoming edges, is it
    -- is guaranteed that no other nodes should come before them in the ordering.
    -- Insert with NULL for Ordinal, as we will set this when we process the node.
    INSERT INTO tmp_topological_sort_order (node, ordinal)
    SELECT n.node, NULL as ordinal
    FROM tmp_nodes n
    WHERE NOT EXISTS (
        SELECT 1 FROM tmp_graph_edges e WHERE e.node_to = n.node limit 1
    );

    -- DECLARE @CurrentNode int,    -- The current node being processed.
    --      @Counter int = 0    -- Counter to assign values to the Ordinal column.

    -- Loop until we are done.
    LOOP
        -- Reset the variable, so we can detect getting no records in the next step.
        _current_node = NULL;

        -- Select any node with [ordinal IS NULL] that is currently in our
        -- tmp_topological_sort_order table, as all nodes with [ordinal IS NULL] in this table has either
        -- no incoming edges or any nodes with edges to it have already been processed.
        SELECT tso.node
        into   _current_node
        FROM   tmp_topological_sort_order tso
        WHERE  tso.ordinal IS NULL
        order  by tso.node
        limit  1;
        
        -- If there are no more such nodes, we are done
        IF _current_node IS NULL THEN
            EXIT;
        END IF;
        
        -- We are processing this node, so set the Ordinal column of this node to the
        -- counter value and increase the counter.
        UPDATE tmp_topological_sort_order tso
        SET    ordinal = _counter
        WHERE  tso.node = _current_node;

        _counter = _counter + 1;
        
        -- This is the complex part. Select all nodes that has exactly ONE incoming
        -- edge - the edge from @CurrentNode. Those nodes can follow @CurrentNode
        -- in the topological ordering because the must not come after any other nodes,
        -- or those nodes have already been processed and inserted earlier in the
        -- ordering and had their outgoing edges removed in the next step.
        INSERT INTO tmp_topological_sort_order (node, ordinal)
        SELECT n.node, NULL
        FROM tmp_nodes n
        JOIN tmp_temp_graph_edges e1 ON n.node = e1.node_to -- Join on edge destination
        WHERE e1.node_from = _current_node AND  -- Edge starts in @CurrentNode
            NOT EXISTS (                            -- Make sure there are no edges to this node
                SELECT 1 FROM tmp_temp_graph_edges e2   -- other then the one from @CurrentNode.
                WHERE e2.node_to = n.node AND e2.node_from <> _current_node
                limit 1
            );
        
        -- Last step. We are done with @CurrentNode, so remove all outgoing edges from it.
        -- This will "free up" any nodes it has edges into to be inserted into the topological ordering.
        DELETE FROM tmp_temp_graph_edges WHERE node_from = _current_node;
    END LOOP;

    -- If there are edges left in our graph after the algorithm is done, it
    -- means that it could not reach all nodes to eliminate all edges, which
    -- means that the graph must have cycles and no topological ordering can be produced.
    IF EXISTS (SELECT 1 FROM tmp_temp_graph_edges limit 1) then
        raise exception 'the graph contains cycles and no topological ordering can be produced';
        -- SELECT node_from, node_to FROM tmp_temp_graph_edges
    ELSE
        -- Select the nodes ordered by the topological ordering we produced.
        RETURN QUERY
        SELECT n.node, o.ordinal as sort_order
        FROM tmp_nodes n
        JOIN tmp_topological_sort_order o ON n.node = o.node
        ORDER BY o.ordinal;
    END IF;

    -- clean up, return.
    DROP TABLE tmp_temp_graph_edges;
    DROP TABLE tmp_topological_sort_order;
    DROP TABLE tmp_graph_edges;
    DROP TABLE tmp_nodes;

    RETURN;
END;
$BODY$ language plpgsql volatile;


-- select array[('node1', 'node1')::graph_edges, ('node2', 'node1')::graph_edges]::graph_edges[]

-- select * from topological_sort('{"(node1,node1)","(node2,node1)"}'::graph_edges[])

-- select * from topological_sort('{"(3,8)", "(3,10)", "(5,11)", "(7,8)", "(7,11)", "(8,9)", "(11,2)", "(11,9)", "(11,10)"}'::graph_edges[])
