from app import app
import json
import os
import tkinter as tk
from tkinter import scrolledtext


def get_user_input(prompt):
    return input(prompt)


def clear_terminal():
    os.system('cls' if os.name == 'nt' else 'clear')


def send_request(client, conversation_id, user_input):
    request_data = {
        "query": user_input,
        "user_id": "test_user"
    }
    if conversation_id:
        request_data["conversation_id"] = conversation_id

    response = client.post(
        '/handle_request', data=json.dumps(request_data), content_type='application/json')
    return response.get_json()


def send_confirmation(client, conversation_id, user_input, confirmation):
    confirmation_data = {
        "query": user_input,
        "user_id": "test_user",
        "confirmation": confirmation
    }
    if conversation_id:
        confirmation_data["conversation_id"] = conversation_id

    confirm_response = client.post(
        '/confirm_new_story', data=json.dumps(confirmation_data), content_type='application/json')
    return confirm_response.get_json()


def main():
    with app.app_context():
        client = app.test_client()
        conversation_id = None
        pending_confirmation = False
        last_user_input = ""

        def on_send():
            nonlocal conversation_id, pending_confirmation, last_user_input
            user_input = entry.get()
            if user_input.lower() in ['exit', 'quit']:
                root.destroy()
                return

            response_data = send_request(client, conversation_id, user_input)

            if response_data is None:
                chat_log.insert(
                    tk.END, "Error: No response data received. The server might have encountered an error.\n")
                return

            if "confirmation" in response_data:
                chat_log.insert(
                    tk.END, f"Bot: {response_data['confirmation']}\n")
                last_user_input = user_input
                pending_confirmation = True
                yes_button.pack(padx=10, pady=5, side=tk.LEFT)
                no_button.pack(padx=10, pady=5, side=tk.RIGHT)
            else:
                chat_log.insert(
                    tk.END, f"Bot: {response_data.get('response', response_data.get('message', 'Error'))}\n")
                conversation_id = response_data.get('conversation_id')

            entry.delete(0, tk.END)

        def on_yes():
            nonlocal conversation_id, pending_confirmation
            confirm_response_data = send_confirmation(
                client, conversation_id, last_user_input, 'y')

            if confirm_response_data is None:
                chat_log.insert(
                    tk.END, "Error: No response data received. The server might have encountered an error.\n")
                return

            chat_log.delete('1.0', tk.END)
            chat_log.insert(tk.END, "Bot: New story initiated.\n")
            conversation_id = confirm_response_data.get('conversation_id')
            chat_log.insert(
                tk.END, f"Bot: {confirm_response_data.get('response', 'Error')}\n")
            pending_confirmation = False
            yes_button.pack_forget()
            no_button.pack_forget()

        def on_no():
            nonlocal pending_confirmation
            chat_log.insert(tk.END, "Bot: New story request canceled.\n")
            pending_confirmation = False
            yes_button.pack_forget()
            no_button.pack_forget()

        root = tk.Tk()
        root.title("Chatbot")

        chat_log = scrolledtext.ScrolledText(
            root, wrap=tk.WORD, width=50, height=20)
        chat_log.pack(padx=10, pady=10)

        entry = tk.Entry(root, width=50)
        entry.pack(padx=10, pady=10)
        entry.bind("<Return>", lambda event: on_send())

        send_button = tk.Button(root, text="Send", command=on_send)
        send_button.pack(padx=10, pady=10)

        yes_button = tk.Button(root, text="Yes", command=on_yes)
        no_button = tk.Button(root, text="No", command=on_no)

        root.mainloop()


if __name__ == '__main__':
    main()
