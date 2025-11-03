module.exports = async function (context, req) {
    const email = req.query.email;
    context.log(`JavaScript HTTP trigger function processed a request for email: ${email}`);

    // In a real app, you would look this up in a database (e.g., Cosmos DB)
    const userDatabase = {
        "jane.doe@example.com": "user-abc-12345",
        "john.doe@example.com": "user-xyz-67890"
    };

    const userId = userDatabase[email] || null;

    if (userId) {
        context.res = {
            status: 200,
            body: { userId: userId }
        };
    } else {
        context.res = {
            status: 404,
            body: { error: "User not found" }
        };
    }
};
