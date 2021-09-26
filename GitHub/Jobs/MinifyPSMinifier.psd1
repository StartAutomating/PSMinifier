@{
    "runs-on" = "ubuntu-latest"
    steps = @('Checkout','UseMinifierAction', 'OutputMinifier', 'UseMinifierActionGZip', 'OutputMinifierGZip', 'PublishMinified')
}