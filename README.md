# Zig Bison

A simple json parse to learn zig

Bison sort of sounds like json and bison are pretty fast


## How To Use
 There are two modes, formatting and searching. If no filter is passed, the json is 
 parsed, formatted, and echoed back to stdout. If you pass a filter, the first object 
 that matches the filter is returned. See [Filter Syntax](#filter-syntax) for more
 information on the filter syntax.  You can also pipe data in via stdin. For example, 
 the following command will parse the json returned from the API call and find an object
 that has key value pairs that matches both filter segments. 
 ```bash
curl 'https://jsonplaceholder.typicode.com/users/1/todos' -s | zj 'tie=hi.id=9'
```

If there is no stdin and you want to pass the json in as an arg, the second arg becomes the filter:
```bash
zj '{"name": "Jack", "is_cool": true"}' 'na=Jac.cool=TUE'
```

## Filter Syntax
The filter uses a fzf like syntax, it matches the filter characters exist in order and 
is case-insensitive. For example, `hll` would match the string `Hello!` but `llh` would not.

You can filter by key/value pairs too, if an object doesnt contain a matching key/value pair, its
ignored.  To filter, seperate the key and value filters with an `=` (`key_search=value_search`).

You can chain filters together. `people.name=Jack.iscool=tru` would filter down the following json
```json
{
  "id": "12",
  "people": [
    {
      "name": "Bill",
      "is_cool": true,
      "id": 1
    },
    {
      "name": "jack",
      "is_cool": false,
      "id": 2
    },
    {
      "name": "jack",
      "is_cool": true,
      "id": 3
    }
  ],
  "is_active": true
}
```

to find the third object of the people array
```json
{
  "name": "jack",
  "is_cool": true,
  "id": 3
}
```

