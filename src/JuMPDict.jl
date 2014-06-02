using Base.Meta
# multivarate "dictionary" used for collections of variables/constraints

abstract JuMPContainer

abstract JuMPDict{T} <: JuMPContainer

type JuMPDict{T,N}
    tupledict::Dict{NTuple{N},T}
    name::String
end

JuMPDict{T,N}(name::String) =
    JuMPDict{T,N}(Dict{NTuple{N},T}(), name)

Base.getindex(d::JuMPDict, t...) = d.tupledict[t]
Base.setindex!(d::JuMPDict, value, t...) = (d.tupledict[t] = value)

# generate and instantiate a type which is indexed by the given index sets
# the following types of index sets are allowed:
# 0:K -- range with compile-time starting index
# S -- general iterable set
macro gendict(instancename,T,idxsets...)
    N = length(idxsets)
    allranges = all([isexpr(s,:(:)) for s in idxsets])
    if allranges
        # JuMPArray
    else
        # JuMPDict
        return quote
            $(esc(instancename)) = JuMPDict{$T,$N}($instancename)
        end

    end
    offset = Array(Int,N)

    for i in 1:N
        if isexpr(idxsets[i],:(:))
            isrange[i] = true
            if length(idxsets[i].args) == 3
                hasstep = true
            end
        else
            isrange[i] = false
            dictnames[i] = gensym()
        end
    end

    if all(isrange)
        if hasstep # ...convert UnitRange -> StepRange
            for i in 1:N
                if length(idxsets[i].args) == 2
                    push!(idxsets[i].args, idxsets[i].args[2])
                    idxsets[i].args[2] = 1
                end
            end
        end
        geninstance = :($(esc(instancename)) = JuMPArray(Array($T),$(string(instancename)),$(esc(Expr(:tuple,idxsets...)))))
        for i in 1:N
            push!(geninstance.args[2].args[2].args, :(length($(esc(idxsets[i])))))
        end
        return geninstance
    end

    typecode = :(type $(typename){T} <: JuMPDict{T}; innerArray::Array{T,$N}; name::String;
                        indexsets end)
    builddicts = quote end
    for i in 1:N
        if !isrange[i]
            push!(typecode.args[3].args,:($(dictnames[i])::IntDict))
            push!(builddicts.args, quote 
                $(esc(dictnames[i])) = Dict{eltype($(esc(idxsets[i]))),Int}(); 
                for (j,k) in enumerate($(esc(idxsets[i])))
                    $(esc(dictnames[i]))[k] = j
                end 
            end)
        end
    end
    getidxlhs = :(Base.getindex(d::$(typename)))
    setidxlhs = :(setindex!(d::$(typename),val))
    getidxrhs = :(Base.getindex(d.innerArray))
    setidxrhs = :(setindex!(d.innerArray,val))
    maplhs = :(Base.map(f::Function,d::$(typename)))
    maprhs = :($(typename)(map(f,d.innerArray),d.name,d.indexsets))
    for i in 1:N
        varname = symbol(string("x",i))
        
        if isrange[i]
            push!(getidxlhs.args,:($varname))
            push!(setidxlhs.args,:($varname))

            push!(getidxrhs.args,:(isa($varname, Int) ? $varname+$(offset[i]) : $varname ))
            push!(setidxrhs.args,:($varname+$(offset[i])))
        else
            push!(getidxlhs.args,varname)
            push!(setidxlhs.args,varname)

            push!(getidxrhs.args,:(d.($(Expr(:quote,dictnames[i])))[$varname]))
            push!(setidxrhs.args,:(d.($(Expr(:quote,dictnames[i])))[$varname]))
            push!(   maprhs.args,:(d.($(Expr(:quote,dictnames[i])))))
        end
    end

    badgetidxlhs = :(Base.getindex(d::$(typename),wrong...))
    badgetidxrhs = :(error("Wrong number of indices for ",d.name,
                           ", expected ",length(d.indexsets)))

    funcs = :($getidxlhs = $getidxrhs; $setidxlhs = $setidxrhs;
              $maplhs = $maprhs; $badgetidxlhs = $badgetidxrhs)
    geninstance = :($(esc(instancename)) = $(typename)(Array($T),$(string(instancename)),$(esc(Expr(:tuple,idxsets...)))))
    for i in 1:N
        push!(geninstance.args[2].args[2].args, :(length($(esc(idxsets[i])))))
        if !isrange[i]
            push!(geninstance.args[2].args, esc(dictnames[i]))
        end
    end
    eval(Expr(:toplevel, typecode))
    eval(Expr(:toplevel, funcs))

    quote
        $builddicts
        $geninstance
    end

end

# duck typing approach -- if eltype(innerArray) doesn't support accessor, will fail
for accessor in (:getValue, :getDual, :getLower, :getUpper)
    @eval $accessor(x::JuMPContainer) = map($accessor,x)
end

# delegate zero-argument functions
for f in (:(Base.endof), :(Base.ndims), :(Base.length), :(Base.abs))
    @eval $f(x::JuMPContainer)  = $f(x.innerArray)
end
# delegate one-argument functions
for f in (:(Base.size),)
    @eval $f(x::JuMPContainer,k) = $f(x.innerArray,k)
end

(-)(x::JuMPContainer,y::Array) = x.innerArray-y

Base.eltype{T}    (x::JuMPDict{T}) = T

Base.full(x::JuMPContainer) = x

export @gendict
