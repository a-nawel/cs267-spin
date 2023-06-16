#define N 3 /*the number of nodes*/

typedef ROUTE {
  byte path[N] ;
  byte hops; /*length of the path*/
};
ROUTE g_curBestRoute[N] ; /*current best route from each node to destination node 0*/

typedef EDGE {
  bit ed[N] ; /* if positive, then there is a connection from this node to node indexed*/
  chan ch[N] = [1] of {ROUTE}; // if connection exists, channel to node indexed
};
EDGE g_edge[N] ; /*g_edge[i].ed[j], the adjacency matrix (connection from i to j)*/


/*Push node id to the end of route r*/
inline pushPath(/*ROUTE*/ r, /*byte*/ id)
{
  r.path[r.hops] = id ;
  r.hops++;
}

/*Remove the last element of route r*/
inline popPath( /*ROUTE*/ r )
{
  r.hops--;
}

#define isPathEmpty(/*ROUTE*/ r) (r.hops==0)
#define isPathFull(/*ROUTE*/ r) (r.hops==N)


/*Check if there is a cycle from id to id*/
inline checkCycle( /*ROUTE*/ r, /*byte*/ id, /* bit */ ret)
{
  printf("-- Entering checkCycle from %d to %d\n", id, id);
  byte k;
  k = r.hops;
  ret = 0;
  if
  :: isPathFull(r)->ret = 1; /*has a cycle*/
  :: else ->
     do
     :: k>0 ->
        if
        :: r.path[k-1] == id ->
           ret = 1;
           break; /*has a cycle*/
        :: else -> k--;
        fi;
     :: else -> break;
     od;
  fi;
  printf("-- Exiting checkCycle from %d to %d with ret = %d\n", id, id, ret);
}


/*Copy route r2 to r1 , i .e. , r1 = r2*/
inline assign ( /*ROUTE*/ r1 , /*ROUTE*/ r2)
{
   printf("-- Entering assign\n");
  byte n;
  r1.hops = r2.hops;
  n = r2.hops;
  do
  :: n>0 ->
     r1.path[n-1] = r2.path[n-1];
     n--;
  :: else -> break;
  od;
  printf("-- Exiting assign\n");
}


/*Node id sends cbr to neighbors*/
inline routeSend( /*byte*/ id, /*ROUTE*/ cbr)
{
  printf("-- Entering routeSend from node %d\n", id); 
  byte j = 0;
  ROUTE temp;
  do
  :: j<N&& j!=id ->
     if
     :: g_edge[id].ed[j]==1 ->
        printf("Sending: %d to %d\n", id, j);
        if
        :: nfull (g_edge[id].ch[j]) ->
           g_edge[id].ch[j] ! cbr ;
        :: full (g_edge[id].ch[j]) ->
            /* if old msg in channel*/
            /*then remove the old msg*/
            /*and send the new msg*/
           g_edge[id].ch[j] ? temp;
           g_edge[id].ch[j] ! cbr ;
        fi;
     :: else -> skip;
     fi;
     j++;
  :: j<N&& j==id -> j++;
  :: j>=N-> break;
  od;
  printf("-- Exiting routeSend from node %d\n", id);
}



/*Select a better route in cbr and newRoute,
  according to the applied policy*/
/* If ret equals 1, select the new route .
  Otherwise , select cbr . */
inline routeSelect ( /*ROUTE*/ cbr ,
  /*ROUTE*/ newRoute, /* bit */ ret )
{
   printf("-- Entering routeSelect\n");
  ret = 0;
  if
  :: isPathEmpty(cbr ) -> ret = 1;
  :: else ->
     if
     :: cbr.hops > newRoute.hops ->
        /*shorter is better*/
        ret = 1;
     :: cbr.hops == newRoute.hops ->
        if
        :: cbr.path[cbr.hops-2] >
             newRoute.path[newRoute.hops-2] ->
           ret = 1;
           // because path[cbr.hops-1] is the next hop from current node
        :: else -> ret = 0;
        fi;
     :: else -> ret = 0;
     fi;
  fi;
  printf("-- Exiting routeSelect\n");
}


/*Run the routing protocol on the node id*/
/*assume node 0 is the unique destination*/
proctype node(byte id )
{
  ROUTE routeRec; /*store route received*/
  byte i;

  atomic {
  /* initialize a route from 0 to 0*/
  if
  :: id==0 ->
     pushPath(g_curBestRoute[id], 0) ;
     routeSend(id, g_curBestRoute[id]) ;
  :: else -> skip;
  fi;
  }

  i=0;
endASn: 
  do
  :: i<N && i!=id ->
     if
     :: g_edge[i].ed[id]==1 ->
        if
        :: true -> atomic{
           g_edge[i].ch[id] ? [routeRec] -> g_edge[i].ch[id] ? routeRec;
           //full (g_edge[i].ch[id]) -> g_edge[i].ch[id] ? routeRec;
           bit hasCycle;
           checkCycle(routeRec, id, hasCycle) ;
           if
           :: hasCycle == 0 -> /*no cycle*/
              pushPath(routeRec , id) ;
              bit ret;
              routeSelect (g_curBestRoute[id],
                  routeRec, ret);
              if
              :: ret == 1 ->
                 assign(g_curBestRoute[id] ,
                     routeRec);
                 routeSend(id,
                     g_curBestRoute[id]) ;
              :: ret == 0 -> skip;
              fi;
           :: hasCycle == 1 -> skip;
           fi;
           } /*end atomic*/
        :: else -> skip;
        fi;
     :: else -> skip;
     fi;
     i++;
  :: i<N && i==id -> i++;
  :: i>=N-> i=0;
  od;
}

// LTL property
ltl p { <>[] (len(g_edge[1].ch[2])==0) } //OK!
//ltl p { <>[] (len(g_edge[0].ch[2])==0) } //KO!!
//ltl p { <>[] (len(g_edge[0].ch[1])==0) } 

init
{
  byte i=0;
  byte j=1;

   printf("-- Start generating the topology\n");

  atomic {
  /*nondeterministically generate a topology*/
  do
  :: i<N->
     do
     :: j<N->
        if
        :: g_edge[i].ed[j]=1;
           g_edge[j].ed[i]=1;
           printf("-- Created edge (%d <--> %d)\n", i, j);
        :: skip;
        fi;
        j++;
     :: else -> break;
     od;
     i++;
     j=i+1;
  :: else -> break;
  od;
  }

  printf("-- Finished generating the topology\n");

  atomic { /*run nodes 0,1,2, ... ,N-1*/
  i=N;
  do
  :: i>0 ->
     printf("-- Creating node %d...\n", i-1);
     run node(i-1);
     i--;
  :: i==0 -> break;
  od;
  }
  printf("-- Finished creating nodes\n");
}



