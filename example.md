# Mather

Mather is a library for doing maths.

    Mather = require 'mather'
    mather = new Mather()


## Prune me

Even if there is some before-each code:

  foo = "bar"

### Prune me too

Because there are no assertions

```md
<!-- file: "some-file.md" -->
# Even if I have a file
```

## Adding

You can add two numbers:

    result = mather.add 3, 4
    expect(result).toEqual 7

You can add more than two numbers

    result = mather.add 3, 4, 5
    expect(result).toEqual 12

### Foo

    foo = "bar"
    bar = "baz"
    mather = new Mather()

This is a thing

    expect(mather.add foo, bar).toEqual 2

## Subtracting

You can subtract two numbers:

    result = mather.subtract 4, 3
    expect(result).toEqual 1

You can subtract more than two numbers:

    result = mather.subtract 4, 3, 2
    expect(result).toEqual -1
