# -------------------------------------------------------------------------------------------------
#  Copyright (C) 2015-2026 Nautech Systems Pty Ltd. All rights reserved.
#  https://nautechsystems.io
#
#  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
#  You may not use this file except in compliance with the License.
#  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# -------------------------------------------------------------------------------------------------

from datetime import date as pydate
from decimal import Decimal

import pandas as pd

from nautilus_trader.core import nautilus_pyo3

from cpython.datetime cimport date

from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.model.identifiers cimport InstrumentId


cdef class RolloverInterestCalculator:
    """
    Provides rollover interest rate calculations.

    The underlying rate computation is delegated to the Rust implementation
    exposed through PyO3.

    Parameters
    ----------
    data : pd.DataFrame
        The short term interest rate data.
    """

    def __init__(self, data not None: pd.DataFrame):
        # Group the source data by currency for the legacy `get_rate_data` accessor
        self._rate_data = {
            "AUD": data.loc[data["LOCATION"] == "AUS"],
            "CAD": data.loc[data["LOCATION"] == "CAN"],
            "CHF": data.loc[data["LOCATION"] == "CHE"],
            "EUR": data.loc[data["LOCATION"] == "EA19"],
            "USD": data.loc[data["LOCATION"] == "USA"],
            "JPY": data.loc[data["LOCATION"] == "JPN"],
            "NZD": data.loc[data["LOCATION"] == "NZL"],
            "GBP": data.loc[data["LOCATION"] == "GBR"],
            "RUB": data.loc[data["LOCATION"] == "RUS"],
            "NOK": data.loc[data["LOCATION"] == "NOR"],
            "CNY": data.loc[data["LOCATION"] == "CHN"],
            "CNH": data.loc[data["LOCATION"] == "CHN"],
            "MXN": data.loc[data["LOCATION"] == "MEX"],
            "ZAR": data.loc[data["LOCATION"] == "ZAF"],
        }

        # The Rust calculator owns the location-to-currency mapping, so forward every record
        cdef list records = [
            nautilus_pyo3.InterestRateRecord(str(row.LOCATION), str(row.TIME), float(row.Value))
            for row in data.itertuples()
        ]
        self._calculator = nautilus_pyo3.RolloverInterestCalculator(records)

    cpdef object get_rate_data(self):
        """
        Return the short-term interest rate data grouped by currency.

        Returns
        -------
        dict[str, pd.DataFrame]

        """
        return self._rate_data

    cpdef object calc_overnight_rate(self, InstrumentId instrument_id, date date):
        """
        Return the rollover interest rate between the given base currency and quote currency.

        Parameters
        ----------
        instrument_id : InstrumentId
            The forex instrument ID for the calculation.
        date : date
            The date for the overnight rate.

        Returns
        -------
        Decimal

        Raises
        ------
        ValueError
            If `instrument_id.symbol` length is not in range [6, 7].
        RuntimeError
            If no rate data exists for the instrument on the given date.

        Notes
        -----
        1% = 0.01 bp

        """
        Condition.not_none(instrument_id, "instrument_id")
        Condition.not_none(date, "date")
        Condition.in_range_int(len(instrument_id.symbol.value), 6, 7, "len(instrument_id)")

        # Normalize any date-like input (e.g. `pd.Timestamp`) to a plain date for PyO3
        cdef object pyo3_instrument_id = nautilus_pyo3.InstrumentId.from_str(instrument_id.value)
        cdef object rate = self._calculator.calc_overnight_rate(
            pyo3_instrument_id,
            pydate(date.year, date.month, date.day),
        )
        return Decimal(rate)
