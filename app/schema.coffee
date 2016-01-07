unless Zync? then Zync = {}
Zync.Schema =
    instantiate: (type) ->
        recurse = Zync.Schema.instantiate
        type.default ? switch type.name
            when 'any' then undefined
            when 'optional' then undefined
            when 'number' then 0
            when 'string' then ''
            when 'boolean' then false
            when 'dict' then {}
            when 'list'
                if type.size? and type.size > 0
                    _.times(type.size, -> recurse(type.subtype))
                else
                    []
            when 'object'
                result = {}
                for key, subtype of type.fields
                    result[key] = recurse(subtype)
                result
            else
                throw new Error "Type #{type.name} unknown"

    subtype: (schema, prop)  ->
        if schema.name == 'any'
            return name: 'any'
        else if schema.name == 'list' and !prop?
            return schema.subtype
        else if schema.name == 'dict'
            return schema.subtype
        else if schema.name == 'object' and prop of schema.fields
            return schema.fields[prop]
        else
            throw new Error "Could not find subtype of schema #{JSON.stringify schema}, property #{prop}"

