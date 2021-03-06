mutable struct data_type
    n
    nb
    d
    x
    f
    supp
    basis
    coe
    supp1
    ub
    sizes
end

function blockupop_first(f,x;nb=0,newton=true,e=1e-5,reducebasis=false,TS="block",merge=false,QUIET=false,solve=true,extra_sos=false,solution=false,tol=1e-5)
    n=length(x)
    mon=monomials(f)
    coe=coefficients(f)
    lm=length(mon)
    supp=zeros(UInt8,n,lm)
    for i=1:lm
        for j=1:n
            @inbounds supp[j,i]=MultivariatePolynomials.degree(mon[i],x[j])
        end
    end
    d=Int(maxdegree(f)/2)
    if newton==true
       if sum(supp[:,end])!=0
          supp=[supp zeros(UInt8,n)]
          coe=[coe;0]
       end
       basis=newton_basis(n,d,supp,nb=nb,e=e)
    else
       basis=get_basis(n,d,nb=nb)
    end
    if reducebasis==false
       blocks,cl,blocksize,ub,sizes,_=get_blocks(n,supp,basis,nothing,nothing,nb=nb,TS=TS,QUIET=QUIET,merge=merge)
    else
        flag=1
        while flag==1
              blocks,cl,blocksize,ub,sizes,_=get_blocks(n,supp,basis,nothing,nothing,nb=nb,reduce=true,TS=TS,QUIET=QUIET,merge=merge)
              tsupp=[supp zeros(UInt8,n)]
              basis,flag=reducebasis!(n,tsupp,basis,blocks,cl,blocksize,nb=nb)
        end
    end
    opt,supp1,moment=blockupop(n,supp,coe,basis,blocks,cl,blocksize,nb=nb,QUIET=QUIET,solve=solve,solution=solution,extra_sos=extra_sos)
    if solution==true
        sol=extract_solutions(moment,opt,n,0,[f],x,tol=tol)
    else
        sol=nothing
    end
    data=data_type(n,nb,d,x,f,supp,basis,coe,supp1,ub,sizes)
    return opt,sol,data
end

function blockupop_higher!(data;reducebasis=false,TS="block",merge=false,QUIET=false,solve=true,extra_sos=false,solution=false,tol=1e-5)
    n=data.n
    nb=data.nb
    d=data.d
    x=data.x
    f=data.f
    supp=data.supp
    basis=data.basis
    coe=data.coe
    supp1=data.supp1
    ub=data.ub
    sizes=data.sizes
    if reducebasis==false
       blocks,cl,blocksize,ub,sizes,status=get_blocks(n,supp,basis,ub,sizes,nb=nb,TS=TS,QUIET=QUIET,merge=merge)
    else
        flag=1
        while flag==1
              blocks,cl,blocksize,ub,sizes,status=get_blocks(n,supp,basis,ub,sizes,nb=nb,reduce=true,TS=TS,QUIET=QUIET,merge=merge)
              tsupp=[supp zeros(UInt8,n)]
              basis,flag=reducebasis!(n,tsupp,basis,blocks,cl,blocksize,nb=nb)
        end
    end
    opt=nothing
    sol=nothing
    if status==1
        opt,supp1,moment=blockupop(n,supp,coe,basis,blocks,cl,blocksize,nb=nb,QUIET=QUIET,solve=solve,solution=solution,extra_sos=extra_sos)
        if solution==true
            sol=extract_solutions(moment,opt,n,0,[f],x,tol=tol)
        else
            sol=nothing
        end
    end
    data.supp1=supp1
    data.ub=ub
    data.sizes=sizes
    return opt,sol,data
end

function bin_add(bi,bj,nb)
    if nb==0
        return bi+bj
    else
        bs=bi+bj
        bs[1:nb,:]=any.(x->x>0, bs[1:nb,:])
        return bs
    end
end

function get_basis(n,d;nb=0)
    lb=binomial(n+d,d)
    basis=zeros(UInt8,n,lb)
    i=0
    t=1
    while i<d+1
        t=t+1
        if basis[n,t-1]==i
           if i<d
              basis[1,t]=i+1
           end
           i=i+1
        else
            j=findfirst(x->basis[x,t-1]!=0,1:n)
            basis[:,t]=basis[:,t-1]
            if j==1
               basis[1,t]-=1
               basis[2,t]+=1
            else
               basis[1,t]=basis[j,t]-1
               basis[j,t]=0
               basis[j+1,t]+=1
            end
        end
    end
    if nb>0
        basis_bin=basis[1:nb,:]
        basis_valid=all.(x->x<=1, eachcol(basis_bin))
        basis=basis[:, basis_valid]
    end
    return basis
end

function newton_basis(n,d,supp;nb=0,e=1e-5)
    lsupp=size(supp,2)
    basis=get_basis(n,d,nb=nb)
    lb=size(basis,2)
    A0=[-1/2*supp' ones(lsupp,1)]
    t=1
    indexb=[i for i=1:lb]
    temp=sortslices(supp,dims=2)
    while t<=lb
          i=indexb[t]
          if bfind(temp,lsupp,bin_add(basis[:,i],basis[:,i],nb))!=0
             t=t+1
          else
             model=Model(optimizer_with_attributes(Mosek.Optimizer))
             set_optimizer_attribute(model, MOI.Silent(), true)
             @variable(model, x[1:n+1], lower_bound=-10, upper_bound=10)
             @constraint(model, [A0; [basis[:,i]' -1]]*x.<=zeros(lsupp+1,1))
             @objective(model, Min, [basis[:,i]' -1]*x)
             optimize!(model)
             vx=value.(x)
             if abs(objective_value(model))<=e&&sum(abs.(vx))<=e
                t=t+1
             else
                if abs(objective_value(model))<=e&&sum(abs.(vx))>e
                   t=t+1
                else
                   lb=lb-1
                   indexb=deleteat!(indexb,t)
                end
                r=t
                while lb>=r
                      j=indexb[r]
                      if [basis[:,j]' -1]*vx<=-e
                         lb=lb-1
                         indexb=deleteat!(indexb,r)
                      else
                         r=r+1
                      end
                end
             end
          end
    end
    return basis[:,indexb]
end

function generate_basis!(n,supp,basis)
    supp=unique(supp,dims=2)
    supp=sortslices(supp,dims=2)
    lsupp=size(supp,2)
    lb=size(basis,2)
    indexb=UInt32[]
    for i = 1:lb
        for j = i:lb
            bi=basis[:,i]+basis[:,j]
             if bfind(supp,lsupp,bi)!=0
                 push!(indexb,i,j)
             end
        end
    end
    sort!(indexb)
    unique!(indexb)
    return basis[:,indexb]
end

function odd_supp(supp)
    return supp[:,any.(isodd, eachcol(supp))]
end

function even_supp(supp)
    return supp[:,all.(iseven, eachcol(supp))]
end

function comp(a,b)
    i=1
    n=length(a)
    while i<=n
          if a[i]<b[i]
             return -1
          elseif a[i]>b[i]
             return 1
          else
             i+=1
          end
    end
    if i==n+1
       return 0
    end
end

function bfind(A,l,a)
    if l==0
        return 0
    end
    low=1
    high=l
    n=length(a)
    while low<=high
        mid=Int(ceil(1/2*(low+high)))
        if n>1
            order=comp(A[:,mid],a)
        else
            order=comp(A[mid],a)
        end
        if order==0
           return mid
        elseif order<0
           low=mid+1
        else
           high=mid-1
        end
    end
    return 0
end

function get_graph(n,supp,basis;nb=0,reduce=false)
    lb=size(basis,2)
    G=SimpleGraph(lb)
    if reduce==true||nb>0
        tsupp=[supp bin_add(basis,basis,nb)]
        tsupp=unique(tsupp,dims=2)
        tsupp=sortslices(tsupp,dims=2)
        ltsupp=size(tsupp,2)
        for i = 1:lb
            for j = i+1:lb
                 bi=bin_add(basis[:,i],basis[:,j],nb)
                 if bfind(tsupp,ltsupp,bi)!=0
                    add_edge!(G,i,j)
                 end
            end
        end
    else
        osupp=odd_supp(supp)
        osupp=unique(osupp,dims=2)
        osupp=sortslices(osupp,dims=2)
        lo=size(osupp,2)
        for i = 1:lb
            for j = i+1:lb
                bi=basis[:,i]+basis[:,j]
                if all(x->iseven(bi[x]), 1:n)||bfind(osupp,lo,bi)!=0
                   add_edge!(G,i,j)
                end
            end
        end
        tsupp=osupp
    end
    return G,tsupp
end

function get_blocks(n,supp,basis,ub,sizes;nb=0,reduce=false,TS="block",minimize=false,QUIET=true,merge=false)
    if TS==false
        blocksize=[size(basis,2)]
        blocks=[[i for i=1:size(basis,2)]]
        cl=1
    else
        G,_=get_graph(n,supp,basis,nb=nb,reduce=reduce)
        if TS=="block"
            blocks=connected_components(G)
            blocksize=length.(blocks)
            cl=length(blocksize)
        else
            blocks,cl,blocksize=chordal_cliques!(G, method=TS, minimize=minimize)
            if merge==true
                blocks,cl,blocksize=clique_merge!(blocks,cl,QUIET=true)
            end
        end
    end
    nub=unique(blocksize)
    nsizes=[sum(blocksize.== i) for i in nub]
    if ub==nothing||nub!=ub||nsizes!=sizes
        status=1
        if QUIET==false
            println("------------------------------------------------------")
            println("The sizes of blocks:\n$nub\n$nsizes")
            println("------------------------------------------------------")
        end
    else
        status=0
        if QUIET==false
            println("No higher TSSOS hierarchy!")
        end
    end
    return blocks,cl,blocksize,nub,nsizes,status
end

function blockupop(n,supp,coe,basis,blocks,cl,blocksize;nb=0,QUIET=true,solve=true,solution=false,extra_sos=false)
    supp1=zeros(UInt8,n,Int(sum(blocksize.^2+blocksize)/2))
    k=1
    for i=1:cl
        for j=1:blocksize[i]
            for r=j:blocksize[i]
                @inbounds bi=bin_add(basis[:,blocks[i][j]],basis[:,blocks[i][r]],nb)
                @inbounds supp1[:,k]=bi
                k+=1
            end
        end
    end
    supp0=supp1
    if extra_sos==true||solution==true
        supp1=[supp1 get_basis(n,2,nb=nb)]
    end
    supp1=unique(supp1,dims=2)
    supp1=sortslices(supp1,dims=2)
    objv=nothing
    moment=nothing
    if solve==true
        lsupp1=size(supp1,2)
        model=Model(optimizer_with_attributes(Mosek.Optimizer))
        set_optimizer_attribute(model, MOI.Silent(), QUIET)
        cons=[AffExpr(0) for i=1:lsupp1]
        if extra_sos==true||solution==true
            pos0=@variable(model, [1:n+1, 1:n+1], PSD)
            for j=1:n+1
                for k=j:n+1
                    @inbounds bi=bin_add(basis[:,j],basis[:,k],nb)
                    Locb=bfind(supp1,lsupp1,bi)
                    if j==k
                       @inbounds cons[Locb]+=pos0[j,k]
                    else
                       @inbounds cons[Locb]+=2*pos0[j,k]
                    end
                end
            end
        end
        pos=Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl)
        for i=1:cl
            bs=blocksize[i]
            if bs==1
               @inbounds pos[i]=@variable(model, lower_bound=0)
               @inbounds bi=bin_add(basis[:,blocks[i]],basis[:,blocks[i]],nb)
               Locb=bfind(supp1,lsupp1,bi)
               @inbounds cons[Locb]+=pos[i]
            else
               @inbounds pos[i]=@variable(model, [1:bs, 1:bs], PSD)
               for j=1:blocksize[i]
                   for r=j:blocksize[i]
                       @inbounds bi=bin_add(basis[:,blocks[i][j]],basis[:,blocks[i][r]],nb)
                       Locb=bfind(supp1,lsupp1,bi)
                       if j==r
                           @inbounds cons[Locb]+=pos[i][j,r]
                       else
                           @inbounds cons[Locb]+=2*pos[i][j,r]
                       end
                   end
               end
            end
        end
        bc=zeros(1,lsupp1)
        lsupp=size(supp,2)
        for i=1:lsupp
            Locb=bfind(supp1,lsupp1,supp[:,i])
            if Locb==0
               @error "The monomial basis is not enough!"
               return nothing,nothing,nothing
            else
               bc[Locb]=coe[i]
            end
        end
        @variable(model, lower)
        cons[1]+=lower
        @constraint(model, con[i=1:lsupp1], cons[i]==bc[i])
        @objective(model, Max, lower)
        optimize!(model)
        status=termination_status(model)
        if status == MOI.OPTIMAL
           objv = objective_value(model)
           println("optimum = $objv")
        else
           objv = objective_value(model)
           println("termination status: $status")
           sstatus=primal_status(model)
           println("solution status: $sstatus")
           println("optimum = $objv")
        end
        if solution==true
            dual_var=-dual.(con)
            moment=zeros(Float64,n+1,n+1)
            for j=1:n+1
                for k=j:n+1
                    bi=bin_add(basis[:,j],basis[:,k],nb)
                    Locb=bfind(supp1,lsupp1,bi)
                    moment[j,k]=dual_var[Locb]
                end
            end
            moment=Symmetric(moment,:U)
        end
    end
    return objv,supp0,moment
end

function extract_solutions(moment,opt,n,m,pop,x;numeq=0,tol=1e-5)
    F=eigen(moment, n+1:n+1)
    sol=sqrt(F.values[1])*F.vectors[:,1]
    sol=sol[2:end]/sol[1]
    flag=0
    if abs(opt-polynomial(pop[1])(x => sol))>=tol
        flag=1
    end
    for i=1:m-numeq
        if polynomial(pop[i+1])(x => sol)<=-tol
            flag=1
        end
    end
    for i=m-numeq+1:m
        if abs(polynomial(pop[i+1])(x => sol))>=tol
            flag=1
        end
    end
    if flag==0
        println("Global optimality certified!")
    end
    return sol
end

# function comp_to(a,b,n)
#     if sum(a)<sum(b)
#         return -1
#     elseif sum(a)>sum(b)
#         return 1
#     else
#         i=1
#         while i<=n
#             if a[end+1-i]<b[end+1-i]
#                 return -1
#             elseif a[end+1-i]>b[end+1-i]
#                 return 1
#             else
#                 i+=1
#             end
#         end
#     end
#     return 0
# end
#
# function bfind_to(A,l,a,n)
#     if l==0
#         return 0
#     end
#     low=1
#     high=l
#     while low<=high
#         mid=Int(ceil(1/2*(low+high)))
#         order=comp_to(A[:,mid],a,n)
#         if order==0
#            return mid
#         elseif order<0
#            low=mid+1
#         else
#            high=mid-1
#         end
#     end
#     return 0
# end

# function cliquesFromSpMatD(A;dense=10)
#     ms=MSession()
#     mat"lb = size($A,1);
#     A = spones($A) + (2*lb+1)*speye(lb);
#     opts.dense=$dense;
#     I = amd(A,opts);
#     R = chol(A(I,I));
#     Cliques = spones(R);
#     [value,orig_idx] = sort(I);
#     remainIdx = 1;
#     for i=2:lb
#         idx = i:lb;
#         one = find(Cliques(i,idx));
#         noOfone = length(one);
#         cliqueResult = sum(Cliques(remainIdx,idx(one)),2);
#         if isempty(find(cliqueResult == noOfone,1))
#            remainIdx = [remainIdx;i];
#         end
#     end
#     cSet = Cliques(remainIdx,orig_idx);
#     cl = length(remainIdx);
#     [Elem,~] = find(cSet');
#     NoElem = full(sum(cSet,2));"
#     cl=jscalar(get_mvariable(ms,:cl))
#     Elem=jarray(get_mvariable(ms,:Elem))
#     blocksize=jarray(get_mvariable(ms,:NoElem))
#     cl=convert(UInt16,cl)
#     Elem=convert(Array{UInt16},Elem)
#     blocksize=convert(Array{Int},blocksize[1:end])
#     blocks=Vector{Vector{UInt16}}(undef,cl)
#     blocks[1]=Elem[1:blocksize[1]]
#     for i=2:cl
#         idx=sum(blocksize[1:i-1])
#         blocks[i]=Elem[idx+1:idx+blocksize[i]]
#     end
#     return blocks,cl,blocksize
# end

# function get_cliques(n,supp,basis;nb=0,reduce=false,dense=10,QUIET=true,alg="amd",merge=false)
#     lb=size(basis,2)
#     if alg=="greedy"
#         G=CGraph()
#         for i=1:lb
#             cadd_node!(G)
#         end
#     else
#         A=zeros(UInt8,lb,lb)
#     end
#     if reduce==true||nb>0
#         # supp1=[supp 2*basis]
#         supp1=[supp bin_add(basis, basis, nb)]
#         supp1=unique(supp1,dims=2)
#         supp1=sortslices(supp1,dims=2)
#         lsupp1=size(supp1,2)
#         for i = 1:lb
#             for j = i+1:lb
#                 # bi=basis[:,i]+basis[:,j]
#                 bi=bin_add(basis[:,i],basis[:,j],nb)
#                  if bfind(supp1,lsupp1,bi,n)!=0
#                      if alg=="greedy"
#                          cadd_edge!(G,i,j)
#                      else
#                          A[i,j]=1
#                          A[j,i]=1
#                      end
#                 end
#             end
#         end
#     else
#         osupp=odd_supp(supp)
#         osupp=unique(osupp,dims=2)
#         osupp=sortslices(osupp,dims=2)
#         lo=size(osupp,2)
#         for i = 1:lb
#             for j = i+1:lb
#                 bi=basis[:,i]+basis[:,j]
#                 if sum(Int[iseven(bi[k]) for k=1:n])==n||bfind(osupp,lo,bi,n)!=0
#                     if alg=="greedy"
#                         cadd_edge!(G,i,j)
#                     else
#                         A[i,j]=1
#                         A[j,i]=1
#                     end
#                 end
#             end
#         end
#     end
#     if alg=="greedy"
#         blocks,cl,blocksize=chordal_extension(G, GreedyFillIn())
#     else
#         blocks,cl,blocksize=cliquesFromSpMatD(A,dense=dense)
#     end
#     if merge==true
#         blocks,cl,blocksize=clique_merge!(blocks,cl,QUIET=true)
#     end
#     ub=unique(blocksize)
#     sizes=[sum(blocksize.== i) for i in ub]
#     if QUIET==false
#         println("------------------------------------------------------")
#         println("The sizes of blocks:\n$ub\n$sizes")
#         println("------------------------------------------------------")
#     end
#     return blocks,cl,blocksize,ub,sizes
# end
#
# function get_hcliques(n,supp,basis,ub,sizes;nb=0,reduce=false,dense=10,QUIET=true,alg="amd",merge=false)
#     lb=size(basis,2)
#     if alg=="greedy"
#         G=CGraph()
#         for i=1:lb
#             cadd_node!(G)
#         end
#     else
#         A=zeros(UInt8,lb,lb)
#     end
#     if reduce==true||nb>0
#         # supp1=[supp 2*basis]
#         supp1=[supp bin_add(basis, basis, nb)]
#         supp1=unique(supp1,dims=2)
#         supp1=sortslices(supp1,dims=2)
#         lsupp1=size(supp1,2)
#         for i = 1:lb
#             for j = i+1:lb
#                 # bi=basis[:,i]+basis[:,j]
#                 bi=bin_add(basis[:,i],basis[:,j],nb)
#                  if bfind(supp1,lsupp1,bi,n)!=0
#                      if alg=="greedy"
#                          cadd_edge!(G,i,j)
#                      else
#                          A[i,j]=1
#                          A[j,i]=1
#                      end
#                 end
#             end
#         end
#     else
#         osupp=odd_supp(supp)
#         osupp=unique(osupp,dims=2)
#         osupp=sortslices(osupp,dims=2)
#         lo=size(osupp,2)
#         for i = 1:lb
#             for j = i+1:lb
#                 bi=basis[:,i]+basis[:,j]
#                 if sum(Int[iseven(bi[k]) for k=1:n])==n||bfind(osupp,lo,bi,n)!=0
#                     if alg=="greedy"
#                         cadd_edge!(G,i,j)
#                     else
#                         A[i,j]=1
#                         A[j,i]=1
#                     end
#                 end
#             end
#         end
#     end
#     if alg=="greedy"
#         blocks,cl,blocksize=chordal_extension(G, GreedyFillIn())
#     else
#         blocks,cl,blocksize=cliquesFromSpMatD(A,dense=dense)
#     end
#     if merge==true
#         blocks,cl,blocksize=clique_merge!(blocks,cl,QUIET=true)
#     end
#     nub=unique(blocksize)
#     nsizes=[sum(blocksize.== i) for i in nub]
#     if nub!=ub||nsizes!=sizes
#         if QUIET==false
#             println("------------------------------------------------------")
#             println("The sizes of blocks:\n$nub\n$nsizes")
#             println("------------------------------------------------------")
#         end
#         return blocks,cl,blocksize,nub,nsizes,1
#     else
#         if QUIET==false
#             println("No higher TSSOS hierarchy!")
#         end
#         return blocks,cl,blocksize,nub,nsizes,0
#     end
# end

# function blockupopm(n,supp,coe,basis,blocks,cl,blocksize;QUIET=true)
#     supp1=zeros(UInt8,n,Int(sum(blocksize.^2+blocksize)/2))
#     k=1
#     for i=1:cl
#         for j=1:blocksize[i]
#             for r=j:blocksize[i]
#                 @inbounds bi=basis[:,blocks[i][j]]+basis[:,blocks[i][r]]
#                 @inbounds supp1[:,k]=bi
#                 k+=1
#             end
#         end
#     end
#     supp1=unique(supp1,dims=2)
#     supp1=sortslices(supp1,dims=2)
#     opt=nothing
#     if solve==true
#         lsupp1=size(supp1,2)
#         indexb=[i for i=1:cl]
#         oneb=indexb[[blocksize[k]==1 for k=1:cl]]
#         semb=indexb[[blocksize[k]!=1 for k=1:cl]]
#         sblocksize=blocksize[semb]
#         oblocks=blocks[oneb]
#         sblocks=blocks[semb]
#         lone=length(oneb)
#         scl=cl-lone
#         bkc=[MSK_BK_FX for i=1:lsupp1]
#         bc=zeros(1,lsupp1)[1:end]
#         lsupp=size(supp,2)
#         for i=1:lsupp
#             Locb=bfind(supp1,lsupp1,supp[:,i],n)
#             if Locb==0
#                println("INFEASIBLE")
#                return nothing,nothing
#             else
#                bc[Locb]=coe[i]
#             end
#         end
#         consi=[UInt16[] for i=1:lsupp1,j=1:scl]
#         consj=[UInt16[] for i=1:lsupp1,j=1:scl]
#         consk=[Float64[] for i=1:lsupp1,j=1:scl]
#         dims=[sblocksize[j] for i=1:lsupp1,j=1:scl]
#         for i=1:scl
#             for j=1:sblocksize[i]
#                 for r=j:sblocksize[i]
#                     @inbounds bi=basis[:,sblocks[i][j]]+basis[:,sblocks[i][r]]
#                     Locb=bfind(supp1,lsupp1,bi,n)
#                     @inbounds push!(consi[Locb,i],r)
#                     @inbounds push!(consj[Locb,i],j)
#                     @inbounds push!(consk[Locb,i],1.0)
#                 end
#             end
#         end
#         oLocb=zeros(UInt32,lone,1)[1:end]
#         for i=1:lone
#             bi=2*basis[:,oblocks[i][1]]
#             oLocb[i]=bfind(supp1,lsupp1,bi,n)
#         end
#         A=sparse(oLocb,[i for i=1:lone],[1.0 for i=1:lone])
#         maketask() do task
#             if QUIET==false
#                 printstream(msg)=print(msg)
#                 putstreamfunc(task,MSK_STREAM_LOG,printstream)
#             end
#             appendvars(task,1+lone)
#             appendcons(task,lsupp1)
#             appendbarvars(task,sblocksize[1:end])
#             putcj(task,1,1.0)
#             putvarboundslice(task,1,2,[MSK_BK_FR],[-Inf],[+Inf])
#             putvarboundslice(task,2,2+lone,[MSK_BK_LO for i=1:lone],[0 for i=1:lone],[+Inf for i=1:lone])
#             putconboundslice(task,1,lsupp1+1,bkc,bc,bc)
#             putacolslice(task,1,2,[1],[2],[1],[1.0])
#             putacolslice(task,2,2+lone,A.colptr[1:lone],A.colptr[2:lone+1],A.rowval,A.nzval)
#             for k=1:lsupp1
#                 for j=1:scl
#                     cons=appendsparsesymmat(task,dims[k,j],consi[k,j],consj[k,j],consk[k,j])
#                     putbaraij(task,k,j,[cons],[1.0])
#                 end
#             end
#             putobjsense(task,MSK_OBJECTIVE_SENSE_MAXIMIZE)
#             optimize(task)
#             solutionsummary(task,MSK_STREAM_MSG)
#             solsta=getsolsta(task,MSK_SOL_ITR)
#             if solsta==MSK_SOL_STA_OPTIMAL
#                opt=getprimalobj(task,MSK_SOL_ITR)
#                #barx=getbarxj(task,MSK_SOL_ITR,1)
#                println("optimum = $opt")
#             elseif solsta==MSK_SOL_STA_DUAL_INFEAS_CER||solsta==MSK_SOL_STA_PRIM_INFEAS_CER
#                println("Primal or dual infeasibility")
#             else
#                println("Unknown solution status")
#             end
#         end
#     end
#     return opt,supp1
# end

# function extract_solutions(n,m,x,d,pop,numeq,opt,basis,blocks,cl,blocksize,Gram;method="block")
#     lb=size(basis,2)
#     V=0
#     remove=UInt16[]
#     if method=="block"
#         for i=1:cl
#             if blocksize[i]>1
#                 nspace=nullspace(Gram[i], atol=1e-4)
#                 lns=size(nspace,2)
#                 if lns>0
#                     for j=1:lns
#                         u=zeros(lb,1)
#                         u[blocks[i]]=nspace[:,j]
#                         if V==0
#                             V=u
#                         else
#                             V=[V u]
#                         end
#                     end
#                 end
#             elseif abs(Gram[i])<=1e-6
#                  push!(remove, i)
#                  u=zeros(lb,1)
#                  u[blocks[i][1]]=1
#                  if V==0
#                      V=u
#                  else
#                      V=[V u]
#                  end
#             end
#         end
#     elseif method=="chordal"
#         G=zeros(lb,lb)
#         for i=1:cl
#             if blocksize[i]>1
#                 G[blocks[i],blocks[i]]=Gram[i]
#             elseif abs(Gram[i])<=1e-6
#                 push!(remove, i)
#                 G[blocks[i][1],blocks[i][1]]=Gram[i]
#             else
#                 G[blocks[i][1],blocks[i][1]]=Gram[i]
#             end
#         end
#         V=nullspace(G, atol=1e-4)
#     else
#         V=nullspace(Gram, atol=1e-4)
#     end
#     sol=nothing
#     if size(V,2)==1
#         sol=V[:,1]
#         println("------------------------------------------------")
#         println("Global optimality certified!")
#         println("Extract ",1," minimizer.")
#         println("------------------------------------------------")
#     else
#         U,pivots=rref_with_pivots!(Matrix(V'))
#         U=Matrix(U')
#         w=basis[:,pivots]
#         lw=size(w,2)
#         i=d
#         while i>=0
#             j=1
#             flag=1
#             while j<=lw
#                 if sum(w[:,j])==i
#                     flag=0
#                     if lbfind(remove,length(remove),j)==0
#                         return sol
#                     else
#                         index=[k for k=1:lw]
#                         deleteat!(index, j)
#                         w=w[:,index]
#                         U=U[:,index]
#                         lw-=1
#                     end
#                 else
#                     j+=1
#                 end
#             end
#             if flag==1
#                 break
#             else
#                 i-=1
#             end
#         end
#         println("Rank of the moment matrix = ", lw)
#         N=Vector{Matrix{Float64}}(undef, n)
#         for i=1:n
#             kk=UInt16[]
#             temp=zeros(UInt8,n,1)
#             temp[i]=1
#             for j=1:lw
#                 xwj=w[:,j]+temp[:,1]
#                 locb=bfind_to(basis,lb,xwj,n)
#                 kk=push!(kk, locb)
#             end
#             N[i]=U[kk,:]
#         end
#         rands=rand(n,1)
#         rands=rands/sum(rands)
#         M=zeros(lw,lw)
#         for i in 1:n
#             M+=rands[i]*N[i]
#         end
#         F=schur(M)
#         L=F.Z
#         sol=Vector{Float64}[]
#         for i in 1:lw
#             atom=Float64[]
#             for j = 1:n
#                 atom=push!(atom, L[:,i]'*N[j]*L[:,i])
#             end
#             flag=1
#             if lw>1
#                 if m>0
#                     println("------------------------------------------------")
#                     println("check atom ",i)
#                     check=opt-polynomial(pop[1])(x => atom)
#                     println("check global optimality  = ",check)
#                     if abs(check)>1e-2
#                         flag=0
#                     end
#                     if m-numeq>0
#                         for j in 2:m+1-numeq
#                             check=polynomial(pop[j])(x => atom)
#                             println("check inequality ",j-1," = ",check)
#                             if check<-1e-3
#                                 flag=0
#                             end
#                         end
#                     end
#                     if numeq>0
#                         for j in m-numeq+2:m+1
#                             check=polynomial(pop[j])(x => atom)
#                             println("check equality ",j-m+numeq-1," = ",check)
#                             if abs(check)>1e-3
#                                 flag=0
#                             end
#                         end
#                     end
#                 end
#             end
#             if flag==1
#                 push!(sol,atom)
#             end
#         end
#         nsol=length(sol)
#         if nsol>0
#             println("------------------------------------------------")
#             println("Global optimality certified!")
#             println("Extract ",nsol," minimizer.")
#             println("------------------------------------------------")
#         else
#             sol=nothing
#         end
#     end
#     return sol
# end
