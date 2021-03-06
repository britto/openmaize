defmodule Openmaize.Login do
  @moduledoc """
  Module to handle login using the Comeonin password hashing library.

  There are three options:

  * storage - store the token in a cookie, which is the default, or not have Openmaize handle the storage
    * if you are developing an api or want to store the token in sessionStorage, set storage to nil
  * unique_id - the name which is used to identify the user (in the database)
    * the default is `:username`
    * this can also be a function which checks the user input and returns an atom
      * see the Openmaize.Login.Name module for some example functions
  * add_jwt - the function used to add the JSON Web Token to the response
    * the default is `&OpenmaizeJWT.Plug.add_token/3`

  ## Examples with Phoenix

  In the `web/router.ex` file, add the following line (you can use
  a different controller and route):

      post "/login", PageController, :login_user

  And then in the `page_controller.ex` file, add:

      plug Openmaize.Login when action in [:login_user]

  If you want to use `email` to identify the user:

      plug Openmaize.Login, [unique_id: :email] when action in [:login_user]

  If you want to use `email` or `username` to identify the user (allowing the
  end user a choice):

      plug Openmaize.Login, [unique_id: &Openmaize.Login.Name.email_username/1] when action in [:login_user]

  and the `login_user` function could be written like this:

      def login_user(%Plug.Conn{private: %{openmaize_error: message}} = conn, _opts) do
        conn
        |> put_flash(:error, message)
        |> redirect(to: page_path(conn, :index)
      end
      def login_user(%Plug.Conn{private: %{openmaize_info: message}} = conn, _opts) do
        conn
        |> put_flash(:info, message)
        |> redirect(to: user_path(conn, :index)
      end

  """

  import Plug.Conn
  alias Openmaize.Config

  @behaviour Plug

  def init(opts) do
    {Keyword.get(opts, :storage, :cookie),
     Keyword.get(opts, :unique_id, :username),
     Keyword.get(opts, :add_jwt, &OpenmaizeJWT.Plug.add_token/3)}
  end

  @doc """
  Handle the login POST request.

  If the login is successful and `otp_required: true` is not in the
  user model, a JSON Web Token will be added to the conn, either in
  a cookie or in the body of the response. The conn is then returned.

  If `otp_required: true` is in the user model, `conn.private.openmaize_otp_required`
  will be set to true, but no token will be issued yet.
  """
  def call(%Plug.Conn{params: %{"user" => user_params}} = conn,
           {storage, uniq_id, add_jwt}) do
    {uniq, user_id, password} = get_params(user_params, uniq_id)
    Config.db_module.find_user(user_id, uniq)
    |> check_pass(password, Config.hash_name)
    |> handle_auth(conn, {storage, uniq, add_jwt})
  end

  defp get_params(%{"password" => password} = user_params, uniq) when is_atom(uniq) do
    {uniq, Map.get(user_params, to_string(uniq)), password}
  end
  defp get_params(user_params, uniq_func), do: uniq_func.(user_params)

  defp check_pass(nil, _, _), do: Config.get_crypto_mod.dummy_checkpw
  defp check_pass(%{confirmed_at: nil}, _, _),
    do: {:error, "You have to confirm your email address before continuing."}
  defp check_pass(user, password, hash_name) do
    %{^hash_name => hash} = user
    Config.get_crypto_mod.checkpw(password, hash) and {:ok, user}
  end

  defp handle_auth({:ok, %{id: id, otp_required: true}}, conn, {storage, uniq, _}) do
    put_private(conn, :openmaize_otpdata, {storage, uniq, id})
  end
  defp handle_auth({:ok, user}, conn, {storage, uniq, add_jwt}) do
    add_jwt.(conn, user, {storage, uniq})
  end
  defp handle_auth({:error, message}, conn, _opts) do
    put_private(conn, :openmaize_error, message)
  end
  defp handle_auth(_, conn, _opts) do
    put_private(conn, :openmaize_error, "Invalid credentials")
  end
end
