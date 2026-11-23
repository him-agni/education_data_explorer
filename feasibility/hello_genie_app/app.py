"""Hello-world Streamlit app for Phase 0 check 2: can a deployed app call Genie?

Throwaway. It asks one question against the test Genie space and shows the
answer text, the generated SQL, the status and the elapsed time.
"""

import os
import time

import streamlit as st
from databricks.sdk import WorkspaceClient

DEFAULT_QUESTION = "Which division had the biggest drop in enrollment from 2022 to 2023?"

st.title("Genie hello-world")

space_id = os.environ.get("GENIE_SPACE_ID")
if not space_id:
    st.error(
        "GENIE_SPACE_ID is not set. Attach the Genie space as an app resource "
        "with the key 'genie-space', then redeploy."
    )
    st.stop()

question = st.text_input("Question", value=DEFAULT_QUESTION)

if st.button("Ask Genie"):
    started = time.time()
    with st.spinner("Asking Genie (a cold start can take about 30 seconds)..."):
        try:
            client = WorkspaceClient()  # uses the app's service principal
            message = client.genie.start_conversation_and_wait(
                space_id=space_id, content=question
            )
        except Exception as exc:  # show the real error: this is a feasibility test
            st.error(f"{type(exc).__name__}: {exc}")
            st.stop()

    st.caption(f"status: {message.status} | {time.time() - started:.1f} s")
    for attachment in message.attachments or []:
        if attachment.text:
            st.write(attachment.text.content)
        if attachment.query:
            st.code(attachment.query.query, language="sql")
